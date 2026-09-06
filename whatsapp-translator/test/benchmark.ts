// Explicit live-provider benchmark. Never imports the WhatsApp gateway or real history.
import * as fs from 'node:fs';
import * as path from 'node:path';

import { MODELS, createRouter } from '../src/free-router';
import { buildPrompt, maskNames, restoreNames } from '../src/translator';
import cases from './translation-cases';

interface RunRecord {
  model: string;
  caseId?: number;
  tag?: string;
  source?: string;
  reference?: string;
  output?: string;
  latencyMs: number;
  status: string;
  error?: string;
  humanReviewed?: boolean;
}
interface SummaryRecord {
  model: string;
  attempted: number;
  successful: number;
  medianMs: number | null;
  p95Ms: number | null;
  quality: string;
}

const count = Math.max(1, Math.min(cases.length, Number(process.argv[2]) || 6));
const selectedModels = process.argv[3] ? process.argv[3].split(',') : [...MODELS];
const reportPath = path.resolve(__dirname, '../../docs/translation-benchmark' + (process.argv[3] ? '-alternatives' : '') + '.json');
const report: { at: string; syntheticOnly: boolean; fixtureCount: number; requestedPerModel: number;
  liveWhatsAppTested: boolean; runs: RunRecord[]; summary: SummaryRecord[] } = {
  at: new Date().toISOString(), syntheticOnly: true, fixtureCount: cases.length,
  requestedPerModel: count, liveWhatsAppTested: false, runs: [], summary: [],
};
const save = () => fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
(async () => {
  for (const model of selectedModels) {
    const router = createRouter({ attemptMs: 12000, totalMs: 13000 });
    for (const item of cases.slice(0, count)) {
      const masked = maskNames([item.source, ...item.context], item.names);
      const prompt = buildPrompt(masked.texts[0], { context: masked.texts.slice(1), hasPlaceholders: Object.keys(masked.map).length > 0 });
      const start = Date.now();
      try {
        const response = await router.request(prompt, { models: [model] });
        report.runs.push({ model, ...item, output: restoreNames(response.value as string, masked.map),
          latencyMs: Date.now() - start, status: 'success', humanReviewed: false });
      } catch (error) {
        report.runs.push({ model, caseId: item.id, latencyMs: Date.now() - start,
          status: 'error', error: (error as Error).message });
        save();
        // Do not spend remaining quota retrying an unavailable or limited model.
        break;
      }
      save();
      await new Promise((resolve) => setTimeout(resolve, 3200));
    }
    const runs = report.runs.filter((run) => run.model === model);
    const times = runs.filter((run) => run.status === 'success').map((run) => run.latencyMs).sort((a, b) => a - b);
    report.summary.push({ model, attempted: runs.length, successful: times.length,
      medianMs: times.length ? times[Math.floor(times.length / 2)] : null,
      p95Ms: times.length ? times[Math.min(times.length - 1, Math.ceil(times.length * 0.95) - 1)] : null,
      quality: 'References supplied for review; no native-speaker score claimed.' });
    save();
  }
  console.log(JSON.stringify(report.summary, null, 2));
  console.log('Report: ' + reportPath);
})().catch((error) => { save(); console.error((error as Error).message); process.exitCode = 1; });
