import multer from "multer";
import {createClient} from "@supabase/supabase-js";

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {fileSize: 10 * 1024 * 1024}
});
const supabase = process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY
  ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_ANON_KEY)
  : null;
function runMiddleware(req, res, middleware){
  return new Promise((resolve, reject) => middleware(req, res, error => error ? reject(error) : resolve()));
}

export default async function handler(req, res){
  if (req.method !== "POST") return res.status(405).json({error: "Method not allowed."});
  if (!process.env.OCR_SPACE_API_KEY) return res.status(500).json({error: "OCR provider is not configured. Add OCR_SPACE_API_KEY in Vercel and redeploy."});
  const token = req.headers.authorization?.replace(/^Bearer\s+/i, "");
  if (process.env.OCR_ALLOW_ANONYMOUS !== "true") {
    if (!supabase) return res.status(500).json({error: "OCR backend is not configured. Add SUPABASE_URL and SUPABASE_ANON_KEY in Vercel, then redeploy."});
    if (!token) return res.status(401).json({error: "Sign in before using OCR."});
    const {data, error} = await supabase.auth.getUser(token);
    if (error || !data.user) return res.status(401).json({error: "Your session has expired. Sign in again."});
  }
  try{
    await runMiddleware(req, res, upload.single("image"));
    if (!req.file) return res.status(400).json({error: "An image is required."});
    const form = new FormData();
    form.append("file", new Blob([req.file.buffer], {type: req.file.mimetype}), req.file.originalname);
    form.append("apikey", process.env.OCR_SPACE_API_KEY || "helloworld");
    form.append("language", "eng");
    form.append("isTable", "true");
    form.append("OCREngine", "2");
    const response = await fetch("https://api.ocr.space/parse/image", {method: "POST", body: form});
    const result = await response.json();
    if (!response.ok || result.IsErroredOnProcessing) {
      const providerError = Array.isArray(result.ErrorMessage) ? result.ErrorMessage.join(" ") : result.ErrorMessage;
      return res.status(502).json({error: providerError || result.ErrorDetails || "Hosted OCR provider rejected the image."});
    }
    const text = (result.ParsedResults || []).map(item => item.ParsedText || "").join("\n");
    return res.json({text, tsv: "", words: []});
  }catch(error){
    console.error("OCR failed", error);
    return res.status(500).json({error: "OCR failed on the server."});
  }
}

export const config = {
  api: {bodyParser: false}
};
