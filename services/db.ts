
import { User, Drawing, Prompt } from '../types';

const STORAGE_KEYS = {
  USER: 'doodledash_v2_user',
  DRAWINGS: 'doodledash_v2_drawings',
  PROMPTS: 'doodledash_v2_prompts',
};

export const db = {
  getUser: (): User | null => {
    const data = localStorage.getItem(STORAGE_KEYS.USER);
    if (!data) return null;
    const user: User = JSON.parse(data);
    
    // Check for daily reset of votes
    const today = new Date().toISOString().split('T')[0];
    if (user.lastVoteDate !== today) {
      user.votedDrawingIds = [];
      user.lastVoteDate = today;
      db.saveUser(user);
    }
    return user;
  },

  saveUser: (user: User) => {
    localStorage.setItem(STORAGE_KEYS.USER, JSON.stringify(user));
  },

  getDrawings: (): Drawing[] => {
    const data = localStorage.getItem(STORAGE_KEYS.DRAWINGS);
    return data ? JSON.parse(data) : [];
  },

  saveDrawing: (drawing: Drawing) => {
    const drawings = db.getDrawings();
    drawings.push(drawing);
    localStorage.setItem(STORAGE_KEYS.DRAWINGS, JSON.stringify(drawings));
  },

  voteDrawing: (drawingId: string, value: number) => {
    const drawings = db.getDrawings();
    const index = drawings.findIndex(d => d.id === drawingId);
    if (index !== -1) {
      drawings[index].votes += value;
      localStorage.setItem(STORAGE_KEYS.DRAWINGS, JSON.stringify(drawings));
    }
  },

  getPrompts: (): Prompt[] => {
    const data = localStorage.getItem(STORAGE_KEYS.PROMPTS);
    return data ? JSON.parse(data) : [];
  },

  savePrompt: (prompt: Prompt) => {
    const prompts = db.getPrompts();
    prompts.push(prompt);
    localStorage.setItem(STORAGE_KEYS.PROMPTS, JSON.stringify(prompts));
  }
};
