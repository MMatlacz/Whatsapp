// Shared DTO shapes for the Electron main process and the renderer.

export interface MessageDTO {
  id: string;
  chatId: string;
  body: string;
  from?: string;
  fromMe: boolean;
  name: string;
  photo?: string | null;
  timestamp: number;
  hasMedia: boolean;
  mediaType: string;
  quoted?: string | null;
  translation?: string | null;
  edited?: boolean;
  mediaUrl?: string;
  error?: string | null;
  uiToken?: string;
}

export interface GroupInfo {
  id: string;
  name: string;
}

export interface PageResult {
  messages: MessageDTO[];
  hasMore: boolean;
  cursor: string | null;
}