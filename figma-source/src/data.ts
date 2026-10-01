export type ModeId = 'dino' | 'lane' | 'flappy'

export type Mode = {
  id: ModeId
  game: string
  exercise: string
  muscles: string[]
  action: string
  color: string
  limb: string
  code: string
}

export const MODES: Mode[] = [
  {
    id: 'dino',
    game: 'Dino Runner',
    exercise: 'Jumping Jacks',
    muscles: ['Full body', 'Cardio', 'Coordination'],
    action: 'Jack = Jump',
    color: '#d4ff3a',
    limb: 'FEET',
    code: '01',
  },
  {
    id: 'lane',
    game: 'Lane Switcher',
    exercise: 'Side Lunges',
    muscles: ['Quads', 'Glutes', 'Balance'],
    action: 'Lunge L/R = Shift lane',
    color: '#3ae0ff',
    limb: 'KNEES',
    code: '02',
  },
  {
    id: 'flappy',
    game: 'Flappy Flight',
    exercise: 'Arm Raises',
    muscles: ['Deltoids', 'Lats', 'Endurance'],
    action: 'Raise arms = Rise',
    color: '#ff8a1f',
    limb: 'ARMS',
    code: '03',
  },
]

export const PLAYER = { name: 'KAI VEGA', tag: '#0423', badge: 'KV', level: 17 }

export type Row = { name: string; tag: string; badge: string; score: number; date: string }

export const LEADERBOARD: Record<ModeId, Row[]> = {
  dino: [
    { name: 'MARISOL R', tag: '#1187', badge: 'MR', score: 48210, date: 'Sep 28' },
    { name: 'DEV OKAFOR', tag: '#0092', badge: 'DO', score: 45960, date: 'Sep 27' },
    { name: 'KAI VEGA', tag: '#0423', badge: 'KV', score: 41300, date: 'Sep 30' },
    { name: 'JUNO PARK', tag: '#2210', badge: 'JP', score: 39875, date: 'Sep 21' },
    { name: 'THEO LANG', tag: '#0714', badge: 'TL', score: 36120, date: 'Sep 19' },
    { name: 'ASHA NAIR', tag: '#3301', badge: 'AN', score: 33480, date: 'Sep 25' },
    { name: 'RUI SANTOS', tag: '#0058', badge: 'RS', score: 30910, date: 'Sep 14' },
  ],
  lane: [
    { name: 'JUNO PARK', tag: '#2210', badge: 'JP', score: 22740, date: 'Sep 29' },
    { name: 'ASHA NAIR', tag: '#3301', badge: 'AN', score: 21115, date: 'Sep 26' },
    { name: 'THEO LANG', tag: '#0714', badge: 'TL', score: 19870, date: 'Sep 22' },
    { name: 'KAI VEGA', tag: '#0423', badge: 'KV', score: 18400, date: 'Sep 24' },
    { name: 'MARISOL R', tag: '#1187', badge: 'MR', score: 16230, date: 'Sep 12' },
    { name: 'BEA LUND', tag: '#4471', badge: 'BL', score: 15010, date: 'Sep 18' },
  ],
  flappy: [
    { name: 'DEV OKAFOR', tag: '#0092', badge: 'DO', score: 9640, date: 'Sep 20' },
    { name: 'RUI SANTOS', tag: '#0058', badge: 'RS', score: 8815, date: 'Sep 17' },
    { name: 'BEA LUND', tag: '#4471', badge: 'BL', score: 8120, date: 'Sep 15' },
    { name: 'KAI VEGA', tag: '#0423', badge: 'KV', score: 7300, date: 'Sep 11' },
    { name: 'JUNO PARK', tag: '#2210', badge: 'JP', score: 6990, date: 'Sep 09' },
  ],
}

export type Settings = {
  accel: 'CPU' | 'GPU'
  jack: number
  lunge: number
  arm: number
}

export type Result = { reps: number; seconds: number; score: number; latency: number }

export const fmtTime = (s: number) =>
  `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`
