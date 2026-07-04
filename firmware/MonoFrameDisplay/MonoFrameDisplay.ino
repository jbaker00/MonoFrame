// MonoFrameDisplay — CrowPanel ESP32-S3 e-paper picture frame. Supports the
// 4.2" (400x300, default) and 5.79" (792x272, #define PANEL_579) BW panels.
// Wakes every 30 minutes, fetches the latest 1-bit bitmap for YOUR frame
// from the MonoFrame backend, draws it, and deep-sleeps.
//
// No file editing needed: an unprovisioned frame boots into SETUP MODE — it
// broadcasts a "MonoFrame-XXXX" WiFi hotspot and the MonoFrame iOS app sends
// it your WiFi details and frame credentials over HTTP. Everything is stored
// in NVS flash, so one firmware binary works for every user (flash it from
// the web flasher page — see the repo README).
//
// Required Arduino libraries:
//   - GxEPD2          (Jean-Marc Zingg)
//   - Adafruit GFX
// Board: ESP32S3 Dev Module (Elecrow CrowPanel ESP32-S3 4.2" / 5.79").

#include <Arduino.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <esp_mac.h>

#include <GxEPD2_BW.h>
#include <Fonts/FreeSansBold9pt7b.h>
#include <Update.h>

#include "config.h"   // FRAME_BASE_URL (same for everyone)

#define FW_VERSION "2.2.0"

// CrowPanel ESP32-S3 4.2" pin mapping.
#define EPD_PWR    7
#define EPD_MOSI  11
#define EPD_SCK   12
#define EPD_CS    45
#define EPD_DC    46
#define EPD_RST   47
#define EPD_BUSY  48

// Both CrowPanel boards share the pin mapping; the panel driver and geometry
// differ. Define PANEL_579 in config.h to build for the 5.79" (792x272) panel.
#if defined(PANEL_579)
GxEPD2_BW<GxEPD2_579_GDEY0579T93, GxEPD2_579_GDEY0579T93::HEIGHT> display(
    GxEPD2_579_GDEY0579T93(EPD_CS, EPD_DC, EPD_RST, EPD_BUSY));

constexpr int  PANEL_W = 792;
constexpr int  PANEL_H = 272;
#define PANEL_MODEL "crowpanel-5.79"
#else
GxEPD2_BW<GxEPD2_420_GDEY042T81, GxEPD2_420_GDEY042T81::HEIGHT> display(
    GxEPD2_420_GDEY042T81(EPD_CS, EPD_DC, EPD_RST, EPD_BUSY));

constexpr int  PANEL_W = 400;
constexpr int  PANEL_H = 300;
#define PANEL_MODEL "crowpanel-4.2"
#endif
constexpr int  IMG_BYTES = PANEL_W * PANEL_H / 8;
constexpr uint64_t SLEEP_MICROS = 30ULL * 60ULL * 1000000ULL;   // 30 min
constexpr int EPD_ROTATION = 0;

// Consecutive WiFi/HTTP failures before falling back to setup mode (e.g.
// the user changed their router password).
constexpr uint32_t MAX_FAILS_BEFORE_SETUP = 5;
constexpr uint32_t SETUP_MODE_TIMEOUT_MS = 10UL * 60UL * 1000UL;   // 10 min

static uint8_t gImage[IMG_BYTES];
static String  gErrorMsg;

Preferences prefs;

struct FrameConfig {
  String ssid;
  String pass;
  String frameId;
  String token;
  bool provisioned() const {
    return ssid.length() > 0 && frameId.length() > 0 && token.length() > 0;
  }
};

static FrameConfig gCfg;

String deviceName() {
  // Read the factory-burned MAC directly: WiFi.macAddress() returns junk
  // until the WiFi stack is up, which made the name change between the
  // screen, /info, and reboots.
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  char buf[16];
  snprintf(buf, sizeof(buf), "MonoFrame-%02X%02X", mac[4], mac[5]);
  return String(buf);
}

// MARK: - NVS

void loadConfig() {
  prefs.begin("monoframe", true);
  gCfg.ssid    = prefs.getString("ssid", "");
  gCfg.pass    = prefs.getString("pass", "");
  gCfg.frameId = prefs.getString("frameId", "");
  gCfg.token   = prefs.getString("token", "");
  prefs.end();
}

void saveConfig(const FrameConfig& cfg) {
  prefs.begin("monoframe", false);
  prefs.putString("ssid", cfg.ssid);
  prefs.putString("pass", cfg.pass);
  prefs.putString("frameId", cfg.frameId);
  prefs.putString("token", cfg.token);
  prefs.putUInt("fails", 0);
  prefs.end();
}

uint32_t failCount() {
  prefs.begin("monoframe", true);
  uint32_t n = prefs.getUInt("fails", 0);
  prefs.end();
  return n;
}

void setFailCount(uint32_t n) {
  prefs.begin("monoframe", false);
  prefs.putUInt("fails", n);
  prefs.end();
}

// MARK: - Normal mode (fetch + render + sleep)

bool connectWiFi() {
  WiFi.mode(WIFI_STA);
  WiFi.begin(gCfg.ssid.c_str(), gCfg.pass.c_str());
  Serial.printf("WiFi connecting to %s", gCfg.ssid.c_str());
  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 20000) {
    delay(250);
    Serial.print(".");
  }
  Serial.println();
  if (WiFi.status() != WL_CONNECTED) {
    gErrorMsg = "WiFi failed";
    return false;
  }
  Serial.printf("WiFi OK %s\n", WiFi.localIP().toString().c_str());
  return true;
}

// Advertise _monoframe._tcp while awake so the app's optional network scan
// can spot frames. Frames deep-sleep most of the time, so this is best-effort.
void startMDNS() {
  String name = deviceName();
  name.toLowerCase();
  if (MDNS.begin(name.c_str())) {
    MDNS.addService("monoframe", "tcp", 80);
    MDNS.addServiceTxt("monoframe", "tcp", "fw", FW_VERSION);
    MDNS.addServiceTxt("monoframe", "tcp", "provisioned", "true");
  }
}

// Returns true when the network path worked (a 404 "no picture yet" still
// counts as success — the WiFi + credentials are fine).
bool fetchImage(bool& haveImage) {
  haveImage = false;
  String url = String(FRAME_BASE_URL) + "/getFrame?id=" + gCfg.frameId;

  WiFiClientSecure client;
  client.setInsecure();   // Cloud Functions sit behind Google's GFE; skip CA pinning.

  HTTPClient http;
  http.setTimeout(20000);
  if (!http.begin(client, url)) {
    gErrorMsg = "http.begin failed";
    return false;
  }
  http.addHeader("Authorization", String("Bearer ") + gCfg.token);

  int code = http.GET();
  if (code == 404) {
    gErrorMsg = "No picture yet - send one from the app";
    http.end();
    return true;
  }
  if (code != 200) {
    gErrorMsg = "HTTP " + String(code);
    Serial.printf("GET failed: %d\n", code);
    http.end();
    return false;
  }

  int contentLen = http.getSize();
  if (contentLen > 0 && contentLen != IMG_BYTES) {
    Serial.printf("warn: size=%d expected=%d\n", contentLen, IMG_BYTES);
  }

  WiFiClient* stream = http.getStreamPtr();
  size_t got = 0;
  uint32_t lastByteMs = millis();
  while (http.connected() && got < IMG_BYTES && (millis() - lastByteMs) < 10000) {
    size_t avail = stream->available();
    if (avail == 0) {
      delay(5);
      continue;
    }
    int n = stream->readBytes(gImage + got, min(avail, (size_t)(IMG_BYTES - got)));
    if (n > 0) {
      got += n;
      lastByteMs = millis();
    }
  }
  http.end();

  if (got != IMG_BYTES) {
    gErrorMsg = "short read " + String(got);
    Serial.printf("short read: %u/%d\n", (unsigned)got, IMG_BYTES);
    return false;
  }
  haveImage = true;
  gErrorMsg = "";
  Serial.println("image OK");
  return true;
}

void renderImage() {
  display.setRotation(EPD_ROTATION);
  display.setFullWindow();
  display.fillScreen(GxEPD_WHITE);
  // Adafruit-GFX drawBitmap (non-const overload) reads from RAM, MSB-first.
  // NOTE: drawImage writes directly to controller RAM and is then wiped by
  // display(false), which writes the paged buffer over top -> blank panel.
  display.drawBitmap(0, 0, gImage, PANEL_W, PANEL_H, GxEPD_BLACK);
  display.display(false);
}

void renderLines(const String lines[], int count) {
  display.setRotation(EPD_ROTATION);
  display.setFullWindow();
  display.fillScreen(GxEPD_WHITE);
  display.setTextColor(GxEPD_BLACK);
  display.setFont(&FreeSansBold9pt7b);
  int y = 60;
  for (int i = 0; i < count; i++) {
    display.setCursor(20, y);
    display.print(lines[i]);
    y += 30;
  }
  display.display(false);
}

void renderError() {
  String lines[] = { "MonoFrame", "ERR: " + gErrorMsg };
  renderLines(lines, 2);
}

void deepSleepUntilNext() {
  Serial.println("Deep sleep");
  Serial.flush();
  WiFi.disconnect(true, true);
  display.hibernate();
  // Leave EPD_PWR HIGH — toggling LOW puts the panel in a state that the next
  // boot's display.init() cannot fully recover from.
  esp_sleep_enable_timer_wakeup(SLEEP_MICROS);
  esp_deep_sleep_start();
}

void runNormalMode() {
  if (!connectWiFi()) {
    setFailCount(failCount() + 1);
    renderError();
    deepSleepUntilNext();
    return;
  }
  startMDNS();

  bool haveImage = false;
  if (fetchImage(haveImage)) {
    setFailCount(0);
    if (haveImage) {
      renderImage();
    } else {
      String lines[] = { "MonoFrame", "No picture yet -", "send one from the app!" };
      renderLines(lines, 3);
    }
  } else {
    setFailCount(failCount() + 1);
    renderError();
  }
  deepSleepUntilNext();
}

// MARK: - Setup mode (SoftAP provisioning)

WebServer server(80);
static bool gProvisionedNow = false;

void handleInfo() {
  uint8_t mac[6];
  esp_efuse_mac_get_default(mac);
  char macStr[18];
  snprintf(macStr, sizeof(macStr), "%02X:%02X:%02X:%02X:%02X:%02X",
           mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  String json = String("{\"model\":\"" PANEL_MODEL "\",\"mac\":\"") +
                macStr + "\",\"fw\":\"" FW_VERSION "\"," +
                "\"name\":\"" + deviceName() + "\"," +
                "\"provisioned\":" + (gCfg.provisioned() ? "true" : "false") + "}";
  server.send(200, "application/json", json);
}

// POST /provision — form-encoded: ssid, pass, frameId, token.
void handleProvision() {
  FrameConfig cfg;
  cfg.ssid    = server.arg("ssid");
  cfg.pass    = server.arg("pass");
  cfg.frameId = server.arg("frameId");
  cfg.token   = server.arg("token");

  if (!cfg.provisioned()) {
    server.send(400, "application/json",
                "{\"ok\":false,\"error\":\"ssid, frameId and token are required\"}");
    return;
  }
  saveConfig(cfg);
  Serial.printf("Provisioned: ssid=%s frameId=%s\n",
                cfg.ssid.c_str(), cfg.frameId.c_str());
  server.send(200, "application/json", "{\"ok\":true}");
  gProvisionedNow = true;
}

// POST /update — multipart upload of a new app image, flashed over the air
// with Update.h. Only reachable in setup mode (open AP, physical proximity),
// same trust model as /provision. The phone is the only party involved.
void handleUpdateUpload() {
  HTTPUpload& up = server.upload();
  if (up.status == UPLOAD_FILE_START) {
    Serial.printf("OTA start: %s\n", up.filename.c_str());
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
  } else if (up.status == UPLOAD_FILE_WRITE) {
    if (Update.write(up.buf, up.currentSize) != up.currentSize) {
      Update.printError(Serial);
    }
  } else if (up.status == UPLOAD_FILE_END) {
    if (Update.end(true)) {
      Serial.printf("OTA complete: %u bytes\n", (unsigned)up.totalSize);
    } else {
      Update.printError(Serial);
    }
  } else if (up.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
    Serial.println("OTA aborted");
  }
}

void handleUpdateDone() {
  if (Update.hasError()) {
    server.send(500, "application/json",
                "{\"ok\":false,\"error\":\"update failed\"}");
    return;
  }
  // Force the next boot back into setup mode (even on provisioned frames)
  // so the app can reconnect and finish pairing on the new firmware.
  // Provisioning resets the fail counter.
  setFailCount(MAX_FAILS_BEFORE_SETUP);
  server.send(200, "application/json", "{\"ok\":true}");
  uint32_t flushUntil = millis() + 1500;
  while (millis() < flushUntil) server.handleClient();
  Serial.println("Rebooting into new firmware");
  ESP.restart();
}

void runSetupMode() {
  String ap = deviceName();
  Serial.printf("Setup mode — AP %s\n", ap.c_str());

  String lines[] = {
    "MonoFrame - Setup Mode",
    "",
    "1. Open the MonoFrame app",
    "2. Tap Frames > Add a Frame",
    "",
    "Frame hotspot: " + ap,
  };
  renderLines(lines, 6);

  WiFi.mode(WIFI_AP);
  WiFi.softAP(ap.c_str());   // open network, IP 192.168.4.1
  delay(100);

  String mdnsName = ap;
  mdnsName.toLowerCase();
  if (MDNS.begin(mdnsName.c_str())) {
    MDNS.addService("monoframe", "tcp", 80);
    MDNS.addServiceTxt("monoframe", "tcp", "fw", FW_VERSION);
    MDNS.addServiceTxt("monoframe", "tcp", "provisioned", "false");
  }

  server.on("/info", HTTP_GET, handleInfo);
  server.on("/provision", HTTP_POST, handleProvision);
  server.on("/update", HTTP_POST, handleUpdateDone, handleUpdateUpload);
  server.onNotFound([]() { server.send(404, "text/plain", "not found"); });
  server.begin();

  uint32_t start = millis();
  while (millis() - start < SETUP_MODE_TIMEOUT_MS) {
    server.handleClient();
    if (gProvisionedNow) {
      // Let the HTTP response flush, then reboot straight into normal mode
      // so the user's first picture (or the "send one" screen) shows fast.
      uint32_t flushUntil = millis() + 1500;
      while (millis() < flushUntil) server.handleClient();
      Serial.println("Rebooting into normal mode");
      ESP.restart();
    }
    delay(2);
  }

  // Nobody provisioned us; nap and offer setup again on next wake.
  Serial.println("Setup mode timed out");
  deepSleepUntilNext();
}

// MARK: - Boot

void setup() {
  Serial.begin(115200);
  delay(150);
  Serial.println("\nMonoFrameDisplay boot v" FW_VERSION);

  pinMode(EPD_PWR, OUTPUT);
  digitalWrite(EPD_PWR, HIGH);
  delay(100);

  SPI.begin(EPD_SCK, -1, EPD_MOSI, EPD_CS);
  display.init(115200, true, 10, false);

  loadConfig();

  if (!gCfg.provisioned() || failCount() >= MAX_FAILS_BEFORE_SETUP) {
    runSetupMode();
  } else {
    runNormalMode();
  }
}

void loop() {
  // never reached — setup() deep-sleeps or reboots
}
