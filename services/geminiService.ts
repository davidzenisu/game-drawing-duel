
import { GoogleGenAI } from "@google/genai";

const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });

export const getDailyPrompt = async (): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-3-flash-preview',
      contents: "Generate a simple, fun, and creative drawing prompt for a 60-second doodle challenge. One short phrase only (e.g., 'A cat in a spacesuit', 'A grumpy toaster').",
    });
    return response.text || "A mystery object";
  } catch (error) {
    console.error("Error fetching prompt:", error);
    return "A dancing elephant";
  }
};
