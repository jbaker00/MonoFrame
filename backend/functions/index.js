/**
 * MonoFrame backend — multi-user e-ink picture frame delivery.
 *
 * Each frame is identified by a frameId + secret token minted by
 * `registerFrame`. The iOS app uploads a 400x300 1-bit bitmap via
 * `uploadFrame`; the ESP32 device pulls it via `getFrame`.
 *
 * All functions do their own Bearer-token auth (invoker is public).
 * Firestore doc frames/{frameId} stores only sha256(token), never the token.
 */

const {onRequest} = require("firebase-functions/v2/https");
const {logger} = require("firebase-functions");
const admin = require("firebase-admin");
const crypto = require("crypto");

admin.initializeApp();

const BUCKET = "monoframe-app-frames";
// One entry per supported panel: crowpanel-4.2 (400x300), crowpanel-5.79
// (792x272). The backend stores whatever the app dithered; the byte count is
// the only cross-check available.
const ALLOWED_BYTES = new Set([(400 * 300) / 8, (792 * 272) / 8]);
const EXPECTED_BYTES = (400 * 300) / 8; // legacy default for HEAD fallback
const FRAME_ID_ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";
const FRAME_ID_LENGTH = 10;

const runtimeOpts = {
  timeoutSeconds: 30,
  memory: "256MiB",
  region: "us-central1",
  maxInstances: 5,
  invoker: "public",
};

function sha256Hex(s) {
  return crypto.createHash("sha256").update(s, "utf8").digest("hex");
}

function randomFrameId() {
  const bytes = crypto.randomBytes(FRAME_ID_LENGTH);
  let id = "";
  for (let i = 0; i < FRAME_ID_LENGTH; i++) {
    id += FRAME_ID_ALPHABET[bytes[i] % FRAME_ID_ALPHABET.length];
  }
  return id;
}

function objectPath(frameId) {
  return `frames/${frameId}/current.bin`;
}

/**
 * Validates ?id= and Authorization: Bearer <token> against Firestore.
 * Sends the error response itself; returns the frameId on success, else null.
 */
async function authenticate(req, res) {
  const frameId = String(req.query.id || "");
  if (!/^[a-z2-9]{10}$/.test(frameId)) {
    res.status(400).json({error: "Missing or malformed id"});
    return null;
  }
  const auth = req.get("authorization") || "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!/^[0-9a-f]{64}$/.test(token)) {
    res.status(401).json({error: "Unauthorized"});
    return null;
  }
  const doc = await admin.firestore().doc(`frames/${frameId}`).get();
  const expected = doc.exists ? doc.get("tokenHash") : null;
  const actual = sha256Hex(token);
  // Compare against a dummy when the doc is missing so timing stays flat.
  const reference = expected || sha256Hex("missing-frame");
  const ok = crypto.timingSafeEqual(
      Buffer.from(actual, "hex"), Buffer.from(reference, "hex"));
  if (!doc.exists || !ok) {
    res.status(401).json({error: "Unauthorized"});
    return null;
  }
  return frameId;
}

// POST -> {frameId, token}
exports.registerFrame = onRequest(runtimeOpts, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const token = crypto.randomBytes(32).toString("hex");
  const db = admin.firestore();
  for (let attempt = 0; attempt < 5; attempt++) {
    const frameId = randomFrameId();
    const ref = db.doc(`frames/${frameId}`);
    try {
      await ref.create({
        tokenHash: sha256Hex(token),
        created: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`registered frame ${frameId}`);
      res.status(200).json({frameId, token});
      return;
    } catch (err) {
      if (err.code === 6) continue; // ALREADY_EXISTS -> retry with new id
      logger.error("registerFrame failed", err);
      res.status(500).json({error: "register failed"});
      return;
    }
  }
  res.status(500).json({error: "could not allocate frame id"});
});

// POST ?id=<frameId>, Bearer token, body = 1-bit bitmap (size per panel)
exports.uploadFrame = onRequest(runtimeOpts, async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const frameId = await authenticate(req, res);
  if (!frameId) return;

  const body = req.rawBody;
  if (!body || !ALLOWED_BYTES.has(body.length)) {
    res.status(400).json({
      error: `Body must be one of ${[...ALLOWED_BYTES].join(", ")} bytes`,
      received: body ? body.length : 0,
    });
    return;
  }
  try {
    await admin.storage().bucket(BUCKET).file(objectPath(frameId)).save(body, {
      contentType: "application/octet-stream",
      resumable: false,
    });
    logger.info(`uploaded bitmap for frame ${frameId}`);
    res.status(200).json({ok: true, bytes: body.length});
  } catch (err) {
    logger.error("uploadFrame failed", err);
    res.status(500).json({error: "upload failed"});
  }
});

// GET/HEAD ?id=<frameId>, Bearer token -> raw bitmap
exports.getFrame = onRequest(runtimeOpts, async (req, res) => {
  if (req.method !== "GET" && req.method !== "HEAD") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const frameId = await authenticate(req, res);
  if (!frameId) return;

  // Fire-and-forget liveness marker; frameStatus/the app read it to show
  // "last seen" and to confirm setup succeeded.
  admin.firestore().doc(`frames/${frameId}`).update({
    lastSeen: admin.firestore.FieldValue.serverTimestamp(),
  }).catch((err) => logger.warn("lastSeen update failed", err));

  try {
    const file = admin.storage().bucket(BUCKET).file(objectPath(frameId));
    const [exists] = await file.exists();
    if (!exists) {
      res.status(404).json({error: "No picture set yet"});
      return;
    }
    const [meta] = await file.getMetadata();
    res.set("Content-Type", "application/octet-stream");
    res.set("Cache-Control", "no-store");
    res.set("Last-Modified", meta.updated || "");
    res.set("ETag", meta.etag || "");
    if (req.method === "HEAD") {
      res.set("Content-Length", String(meta.size || EXPECTED_BYTES));
      res.status(200).end();
      return;
    }
    const [data] = await file.download();
    if (!ALLOWED_BYTES.has(data.length)) {
      logger.warn(`unexpected bitmap size for ${frameId}: ${data.length}`);
    }
    res.set("Content-Length", String(data.length));
    res.status(200).send(data);
  } catch (err) {
    logger.error("getFrame failed", err);
    res.status(500).json({error: "fetch failed"});
  }
});

// GET ?id=<frameId>, Bearer token -> {lastSeen, hasImage}
exports.frameStatus = onRequest(runtimeOpts, async (req, res) => {
  if (req.method !== "GET") {
    res.status(405).send("Method Not Allowed");
    return;
  }
  const frameId = await authenticate(req, res);
  if (!frameId) return;

  try {
    const doc = await admin.firestore().doc(`frames/${frameId}`).get();
    const lastSeen = doc.get("lastSeen");
    const [hasImage] = await admin.storage().bucket(BUCKET)
        .file(objectPath(frameId)).exists();
    res.set("Cache-Control", "no-store");
    res.status(200).json({
      lastSeen: lastSeen ? lastSeen.toDate().toISOString() : null,
      hasImage,
    });
  } catch (err) {
    logger.error("frameStatus failed", err);
    res.status(500).json({error: "status failed"});
  }
});
