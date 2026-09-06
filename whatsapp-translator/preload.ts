import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('wa', {
  getState: () => ipcRenderer.invoke('wa:getState'),
  getGroups: () => ipcRenderer.invoke('wa:getGroups'),
  getMessages: (groupId: string, limit?: number) => ipcRenderer.invoke('wa:getMessages', groupId, limit),
  getMessagesPage: (groupId: string, limit?: number, before?: string | null) => ipcRenderer.invoke('wa:getMessagesPage', groupId, limit, before),
  send: (groupId: string, text: string) => ipcRenderer.invoke('wa:send', groupId, text),
  reply: (messageId: string, text: string) => ipcRenderer.invoke('wa:reply', messageId, text),
  translate: (messageId: string, uiToken: string) => ipcRenderer.invoke('wa:translate', messageId, uiToken),
  cancelTranslation: (messageId: string, uiToken: string) => ipcRenderer.invoke('wa:cancelTranslation', messageId, uiToken),
  vocabulary: (messageId: string, chatId: string) => ipcRenderer.invoke('wa:vocabulary', messageId, chatId),
  retranslate: (messageId: string, comment: string, uiToken: string) => ipcRenderer.invoke('wa:retranslate', messageId, comment, uiToken),
  editTranslation: (messageId: string, text: string) => ipcRenderer.invoke('wa:editTranslation', messageId, text),
  knownWords: () => ipcRenderer.invoke('wa:knownWords'),
  addKnownWord: (word: string) => ipcRenderer.invoke('wa:addKnownWord', word),
  removeKnownWord: (word: string) => ipcRenderer.invoke('wa:removeKnownWord', word),
  exportLearning: () => ipcRenderer.invoke('wa:export'),
  on: (channel: string, cb: (data: unknown) => void) => {
    const allowed = ['wa:qr', 'wa:ready', 'wa:groups', 'wa:message', 'wa:translation', 'wa:history'];
    if (allowed.includes(channel)) ipcRenderer.on(channel, (_e, data) => cb(data));
  },
});