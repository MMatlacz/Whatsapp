import { readProviderKey } from './auth-store';

// Bounded free-only routing. At most two attempts (primary + one fallback),
// explicit per-attempt and total deadlines, cancellation, a small concurrency
// limit, and a temporary cooldown after rate-limit / server errors.
// No paid-model fallback, no auto-router: `provider.max_price` pins both costs
// to zero and the model list is restricted to explicitly approved free IDs.

export const MODELS = [
  'minimax/minimax-m3:free',
  'google/gemma-4-31b-it:free',
] as const;

const APPROVED_MODELS: readonly string[] = [
  ...MODELS,
  'z-ai/glm-5.2:free',
  'nvidia/nemotron-3.5-lightning:free',
];

const ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions';

export interface AttemptResult {
  value: unknown;
  model: string;
  durationMs: number;
}

export interface AttemptInfo {
  model: string;
  status: 'success' | 'error';
  durationMs: number;
  error?: string;
}

export interface RouterOptions {
  fetchImpl?: (url: string, init: RequestInit) => Promise<unknown>;
  getKey?: () => string;
  attemptMs?: number;
  totalMs?: number;
  concurrency?: number;
  now?: () => number;
}

export interface RequestOptions {
  signal?: AbortSignal;
  models?: readonly string[];
  json?: boolean;
  maxTokens?: number;
  validate?: (text: string) => unknown;
  onAttempt?: (info: AttemptInfo) => void;
}

export interface Router {
  request(prompt: string, options?: RequestOptions): Promise<AttemptResult>;
}

function abortError(message = 'Translation cancelled'): Error {
  const error = new Error(message);
  error.name = 'AbortError';
  return error;
}

export function createRouter(options: RouterOptions = {}): Router {
  const { fetchImpl = (...args) => fetch(...args), getKey = () =>
    (process.env.OPENROUTER_API_KEY || readProviderKey('openrouter')).trim(),
  attemptMs = 9000, totalMs = 20000, concurrency = 2, now = Date.now } = options;
  let running = 0;
  const queue: Array<{ start(): void }> = [];
  const cooldown = new Map<string, number>();

  function acquire(signal: AbortSignal): Promise<() => void> {
    return new Promise((resolve, reject) => {
      const entry: { start(): void } = { start() {
        signal.removeEventListener('abort', cancel);
        running++;
        resolve(() => { running--; drain(); });
      } };
      function cancel(): void {
        const index = queue.indexOf(entry);
        if (index >= 0) queue.splice(index, 1);
        reject(signal.reason || abortError());
      }
      if (signal.aborted) return cancel();
      signal.addEventListener('abort', cancel, { once: true });
      queue.push(entry);
      drain();
    });
  }
  function drain(): void {
    while (running < concurrency && queue.length) {
      const entry = queue.shift();
      if (entry) entry.start();
    }
  }

  async function request(prompt: string, options: RequestOptions = {}): Promise<AttemptResult> {
    const { signal, models = MODELS, json = false, maxTokens = 2048,
      validate = (text: string) => text, onAttempt = () => {} } = options;
    if (!Array.isArray(models) || !models.length || models.length > 2 ||
      new Set(models).size !== models.length || models.some((model) => !APPROVED_MODELS.includes(model))) {
      throw new Error('Only approved free models are allowed, with at most two attempts');
    }
    if (typeof prompt !== 'string' || !prompt.trim() || prompt.length > 24000) {
      throw new Error('Translation prompt must contain 1–24000 characters; nothing was truncated');
    }
    const key = getKey();
    if (!key) throw new Error('A free OpenRouter API key is required (OPENROUTER_API_KEY)');
    const controller = new AbortController();
    const cancelled = () => controller.abort(abortError());
    if (signal?.aborted) cancelled();
    signal?.addEventListener('abort', cancelled, { once: true });
    const totalTimer = setTimeout(() => controller.abort(abortError('Translation deadline exceeded')), totalMs);
    let release: (() => void) | undefined;
    const errors: string[] = [];
    try {
      release = await acquire(controller.signal);
      for (const model of models) {
        if (controller.signal.aborted) throw controller.signal.reason;
        if ((cooldown.get(model) || 0) > now()) {
          errors.push(model + ': temporarily unavailable; retry later');
          continue;
        }
        const attempt = new AbortController();
        const abort = () => attempt.abort(controller.signal.reason);
        controller.signal.addEventListener('abort', abort, { once: true });
        const timer = setTimeout(() => attempt.abort(abortError('Provider timeout')), attemptMs);
        const started = now();
        try {
          const body: Record<string, unknown> = {
            model, messages: [{ role: 'user', content: prompt }],
            temperature: 0.15, max_tokens: Math.min(8192, Math.max(128, maxTokens)),
            reasoning: { enabled: false },
            // No tools, plugins, auto-router or paid model fallback.
            provider: { max_price: { prompt: 0, completion: 0 } },
          };
          // The catalog advertises response_format for Gemma; the other model
          // gets the same JSON instruction and strict local validation.
          if (json && model !== 'nvidia/nemotron-3.5-lightning:free') body.response_format = { type: 'json_object' };
          const res = await fetchImpl(ENDPOINT, { method: 'POST',
            headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + key },
            body: JSON.stringify(body), signal: attempt.signal });
          const response = res as unknown as Response;
          if (!response.ok) {
            const error = new Error('OpenRouter HTTP ' + response.status);
            (error as Error & { status?: number }).status = response.status;
            if (response.status === 429 || response.status >= 500) {
              const retry = response.headers?.get?.('retry-after');
              const seconds = Number(retry);
              const delay = retry && Number.isFinite(seconds) ? seconds * 1000 : 60000;
              cooldown.set(model, now() + Math.min(300000, Math.max(1000, delay)));
            }
            throw error;
          }
          const data = (await response.json()) as { error?: unknown; choices?: Array<{
            finish_reason?: string; error?: unknown; message?: { content?: unknown } }> };
          if (attempt.signal.aborted) throw attempt.signal.reason;
          if (data.error) throw new Error('OpenRouter rejected the request');
          const choice = data.choices?.[0];
          if (choice?.finish_reason !== 'stop' || choice.error) throw new Error('Incomplete provider output');
          const text = choice.message?.content;
          if (typeof text !== 'string' || !text.trim() || text.length > 64000) throw new Error('Invalid provider output');
          const value = validate(text.trim());
          const durationMs = now() - started;
          onAttempt({ model, status: 'success', durationMs });
          return { value, model, durationMs };
        } catch (error) {
          onAttempt({ model, status: 'error', durationMs: now() - started,
            error: attempt.signal.aborted ? 'Provider timeout or cancellation' : (error as Error).message });
          if (controller.signal.aborted) throw controller.signal.reason;
          errors.push(model + ': ' + (attempt.signal.aborted ? 'timeout' : (error as Error).message));
          // Authentication failures affect both models and are not retried.
          if ((error as Error & { status?: number }).status === 401 ||
            (error as Error & { status?: number }).status === 403 ||
            (error as Error & { status?: number }).status === 402) break;
        } finally {
          clearTimeout(timer);
          controller.signal.removeEventListener('abort', abort);
        }
      }
      throw new Error('Free translation unavailable. ' + errors.join(' | '));
    } finally {
      release?.();
      clearTimeout(totalTimer);
      signal?.removeEventListener('abort', cancelled);
    }
  }
  return { request };
}

const router = createRouter();
export const request = router.request;
export default router;