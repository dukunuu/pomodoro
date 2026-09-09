#!/usr/bin/env node
// Runs the report functions straight out of the frozen Service.qml and emits
// the same structure as `Pomodoro --report-dump`. Diffing the two outputs is how
// the Swift port is held to the behavior of the QML original rather than to a
// re-reading of it.
//
//   node Tools/qml-reference.js <dataDir> <outFile>

const fs = require('fs');
const path = require('path');
const os = require('os');

const dataDir = process.argv[2];
const outFile = process.argv[3];
// A frozen copy of the QML service this app was ported from; see
// Tools/reference/README.md. The Qt front end is no longer in this repo.
const qmlPath = path.join(__dirname, 'reference', 'Service.qml');

// Only the pure report/normalization helpers are lifted; anything touching
// `platform`, Process or FileView stays behind.
const WANTED = new Set([
  'pad', 'formatDuration', 'formatReportDuration', 'dateKey', 'dateStartForKey',
  'dayOrdinal', 'shortDateLabel', 'calendarDateLabel', 'dayLabel', 'monthKey',
  'monthLabel', 'monthShortLabel', 'monthParts', 'sessionTimeLabel',
  'sessionRangeLabel', 'entryPhaseLabel', 'entryStatus', 'entryStatusLabel',
  'entryActiveSeconds', 'normalizedSegments', 'normalizedSessions',
  'parsedHistoryEntries', 'isCompletedFocusSession', 'statsForDay',
  'clippedSegments', 'entriesForDay', 'sessionsForDay', 'weeklyStats',
  'monthlyStats', 'allTimeStats', 'timelineRatio', 'normalizePhase',
  'durationForPhase', 'normalizeNote', 'focusCountForDay',
]);

const lines = fs.readFileSync(qmlPath, 'utf8').split('\n');
const extracted = [];
const names = [];
for (let i = 0; i < lines.length; i++) {
  const match = lines[i].match(/^ {4}function (\w+)\(([^)]*)\) \{$/);
  if (!match || !WANTED.has(match[1])) continue;
  const body = [lines[i]];
  for (let j = i + 1; j < lines.length; j++) {
    body.push(lines[j]);
    if (lines[j] === '    }') break;
  }
  extracted.push(body.map((line) => line.slice(4)).join('\n'));
  names.push(match[1]);
}

const missing = [...WANTED].filter((name) => !names.includes(name));
if (missing.length) {
  console.error('could not extract from Service.qml: ' + missing.join(', '));
  process.exit(1);
}

// The QML functions resolve `root.x` and bare `x` against the same object, so
// the generated module provides both.
const moduleSource = `'use strict';
module.exports = function (root) {
  const focusSeconds = root.focusSeconds;
  const shortBreakSeconds = root.shortBreakSeconds;
  const longBreakSeconds = root.longBreakSeconds;
  const longBreakEvery = root.longBreakEvery;
  const currentDate = root.currentDate;
${extracted.join('\n\n')}

${names.map((name) => `  root.${name} = ${name};`).join('\n')}
  return root;
};
`;
const tempFile = path.join(os.tmpdir(), `qml-reference-${process.pid}.js`);
fs.writeFileSync(tempFile, moduleSource);
const build = require(tempFile);
fs.unlinkSync(tempFile);

const now = new Date();
const root = {
  focusSeconds: 25 * 60,
  shortBreakSeconds: 5 * 60,
  longBreakSeconds: 15 * 60,
  longBreakEvery: 4,
  currentDate: now,
  sessions: [],
  // No live phase: the dump is compared against a service with none either.
  phaseStartedAt: 0,
  phaseRunStartedAt: 0,
  phaseElapsedSeconds: 0,
  phasePlannedSeconds: 0,
  phaseSegments: [],
  phase: 'focus',
  running: false,
  activeNote: '',
};
build(root);
root.todayKey = root.dateKey(now);

const historyRaw = fs.readFileSync(path.join(dataDir, 'pomodoro-history.json'), 'utf8');
root.sessions = root.parsedHistoryEntries(historyRaw) || [];

const days = {};
const entries = {};
const keys = new Set(root.sessions.map((entry) => root.dateKey(entry.endedAt)));
keys.add(root.todayKey);
for (const key of [...keys].sort()) {
  const stats = root.statsForDay(key);
  days[key] = {
    sessions: stats.sessions,
    focusSeconds: stats.focusSeconds,
    breakSeconds: stats.breakSeconds,
    breaks: stats.breaks,
    completedBreaks: stats.completedBreaks,
    shortBreaks: stats.shortBreaks,
    longBreaks: stats.longBreaks,
    interruptedFocus: stats.interruptedFocus,
    interruptedBreaks: stats.interruptedBreaks,
    phases: stats.phases,
    focusText: stats.focusText,
    breakText: stats.breakText,
    totalText: stats.totalText,
  };
  entries[key] = root.entriesForDay(key).map((entry) => ({
    id: entry.id,
    phase: entry.phase,
    status: entry.status,
    startedAt: entry.startedAt,
    endedAt: entry.endedAt,
    activeSeconds: entry.activeSeconds,
    note: entry.note || '',
    segments: entry.segments.map((s) => ({ startedAt: s.startedAt, endedAt: s.endedAt })),
  }));
}

const weeks = {};
for (let offset = -10; offset <= 0; offset++) {
  const anchor = new Date(now.getFullYear(), now.getMonth(), now.getDate() + offset * 7);
  const report = root.weeklyStats(anchor);
  weeks[report.startKey] = {
    startKey: report.startKey,
    endKey: report.endKey,
    startLabel: report.startLabel,
    endLabel: report.endLabel,
    sessions: report.sessions,
    focusSeconds: report.focusSeconds,
    breakSeconds: report.breakSeconds,
    maxTotalSeconds: report.maxTotalSeconds,
    averageDayText: report.averageDayText,
    days: report.days.map((day) => ({
      key: day.key, label: day.label, dayNumber: day.dayNumber,
      sessions: day.sessions, breaks: day.breaks,
      focusSeconds: day.focusSeconds, breakSeconds: day.breakSeconds,
    })),
  };
}

const months = {};
for (let offset = -12; offset <= 0; offset++) {
  const date = new Date(now.getFullYear(), now.getMonth() + offset, 1);
  const report = root.monthlyStats(date.getFullYear(), date.getMonth());
  months[report.key] = {
    key: report.key,
    label: report.label,
    shortLabel: report.shortLabel,
    sessions: report.sessions,
    focusSeconds: report.focusSeconds,
    breakSeconds: report.breakSeconds,
    activeDays: report.activeDays,
    maxDaySeconds: report.maxDaySeconds,
    cellCount: report.cells.length,
  };
}

const all = root.allTimeStats();
const payload = {
  todayKey: root.todayKey,
  sessionCount: root.sessions.length,
  days,
  entries,
  weeks,
  months,
  allTime: {
    sessions: all.sessions,
    focusSeconds: all.focusSeconds,
    breakSeconds: all.breakSeconds,
    breaks: all.breaks,
    activeDays: all.activeDays,
    currentStreak: all.currentStreak,
    longestStreak: all.longestStreak,
    interrupted: all.interrupted,
    firstEndedAt: all.firstEndedAt,
    lastEndedAt: all.lastEndedAt,
    averageSessionText: all.averageSessionText,
    maxChartSeconds: all.maxChartSeconds,
    months: all.months.map((month) => ({
      key: month.key, label: month.label, focusSeconds: month.focusSeconds,
      breakSeconds: month.breakSeconds, sessions: month.sessions,
    })),
  },
};

fs.writeFileSync(outFile, JSON.stringify(payload, null, 2) + '\n');
console.log(`wrote ${outFile}`);
