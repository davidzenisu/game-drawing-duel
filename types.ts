
export type ToolType = 'pen' | 'marker' | 'eraser';

export interface Point {
  x: number;
  y: number;
}

export interface Path {
  points: Point[];
  color: string;
  width: number;
  tool: ToolType;
}

export interface User {
  id: string;
  name: string;
  email: string;
  avatar: string;
  drawingsDone: number;
  lastDrawDate: string | null;
  lastVoteDate: string | null;
  votedDrawingIds: string[]; // Track which drawings were voted on today
}

export interface Drawing {
  id: string;
  userId: string;
  userName: string;
  prompt: string;
  svgData: string;
  votes: number;
  createdAt: string; // ISO Date
}

export interface Prompt {
  text: string;
  date: string; // YYYY-MM-DD
}
