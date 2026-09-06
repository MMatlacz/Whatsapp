// Preload bridge (preload.ts) exposed as window.wa.
import type { MessageDTO, GroupInfo, PageResult } from '../src/types';
import type { VocabularyResult } from '../src/vocabulary';

export {};

declare global {
  interface Window {
    wa: {
      getState(): Promise<{ ready: boolean }>;
      getGroups(): Promise<GroupInfo[]>;
      getMessages(groupId: string, limit?: number): Promise<MessageDTO[]>;
      getMessagesPage(groupId: string, limit?: number, before?: string | null): Promise<PageResult>;
      send(groupId: string, text: string): Promise<MessageDTO>;
      reply(messageId: string, text: string): Promise<MessageDTO>;
      translate(messageId: string, uiToken: string): Promise<MessageDTO>;
      cancelTranslation(messageId: string, uiToken: string): Promise<void>;
      vocabulary(messageId: string, chatId: string): Promise<VocabularyResult & { key: string }>;
      retranslate(messageId: string, comment: string, uiToken: string): Promise<MessageDTO>;
      editTranslation(messageId: string, text: string): Promise<{ id: string; translation: string; edited: boolean }>;
      knownWords(): Promise<string[]>;
      addKnownWord(word: string): Promise<string[]>;
      removeKnownWord(word: string): Promise<string[]>;
      exportLearning(): Promise<{ file: string; sentences: number; words: number }>;
      on(channel: string, cb: (data: unknown) => void): void;
    };
  }
}