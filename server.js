import "dotenv/config";
import express from "express";
import cors from "cors";
import multer from "multer";
import path from "node:path";
import {fileURLToPath} from "node:url";
import {createWorker} from "tesseract.js";
import {createClient} from "@supabase/supabase-js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const port = Number(process.env.PORT || 3000);
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {fileSize: 10 * 1024 * 1024}
});
const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY)
  : null;
let workerPromise;

app.use(cors());
app.use(express.static(__dirname));

async function getWorker(){
  if (!workerPromise) workerPromise = createWorker("eng");
  return workerPromise;
}

async function requireAgent(req, res, next){
  if (process.env.OCR_ALLOW_ANONYMOUS === "true") return next();
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (!supabase || !token) return res.status(401).json({error: "Sign in before using OCR."});
  const {data, error} = await supabase.auth.getUser(token);
  if (error || !data.user) return res.status(401).json({error: "Your session has expired. Sign in again."});
  req.user = data.user;
  next();
}

app.post("/api/ocr", requireAgent, upload.single("image"), async (req, res) => {
  if (!req.file) return res.status(400).json({error: "An image is required."});
  try{
    const worker = await getWorker();
    const {data} = await worker.recognize(req.file.buffer);
    const words = (data.words || []).map(word => ({
      block: word.block,
      paragraph: word.paragraph,
      line: word.line,
      text: word.text,
      confidence: word.confidence,
      left: word.bbox?.x0,
      top: word.bbox?.y0,
      width: word.bbox ? word.bbox.x1 - word.bbox.x0 : 0,
      height: word.bbox ? word.bbox.y1 - word.bbox.y0 : 0
    }));
    res.json({text: data.text, tsv: data.tsv || "", words});
  }catch(error){
    console.error("OCR failed", error);
    res.status(500).json({error: "OCR failed on the server."});
  }
});

app.get("/health", (_req, res) => res.json({ok: true, ocr: "server"}));

app.listen(port, () => console.log(`RD Lot Register listening on http://localhost:${port}`));
