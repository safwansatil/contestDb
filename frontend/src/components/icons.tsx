/* Original inline-SVG icon set — no icon library, no emoji.
   All line-based, inherit the theme's ink via currentColor. One cohesive family
   that recolors per theme; the three theme emblems give the switcher its identity. */
import type { CSSProperties } from 'react'

type P = { size?: number; className?: string; style?: CSSProperties; strokeWidth?: number }

function Svg({ size = 20, className, style, strokeWidth = 1.6, children }: P & { children: React.ReactNode }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={strokeWidth} strokeLinecap="round" strokeLinejoin="round"
      className={className} style={{ display: 'block', flex: 'none', ...style }} aria-hidden>
      {children}
    </svg>
  )
}

/* ---- Navigation ---- */
export const IconExplore = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="9" /><path d="M15.5 8.5l-2 5-5 2 2-5z" /></Svg>
export const IconScroll = (p: P) => <Svg {...p}><path d="M7 4h9a2 2 0 0 1 2 2v11a3 3 0 0 0 3 3H9a2 2 0 0 1-2-2z" /><path d="M7 4a2 2 0 0 0-2 2v1h2" /><path d="M10 9h5M10 12.5h5" /></Svg>
export const IconScales = (p: P) => <Svg {...p}><path d="M12 3v16M6 20h12" /><path d="M12 6l-6 2 6-2 6-2" /><path d="M6 8l-2.2 4a2.2 2.2 0 0 0 4.4 0z" /><path d="M18 6l-2.2 4a2.2 2.2 0 0 0 4.4 0z" /></Svg>
export const IconTrophy = (p: P) => <Svg {...p}><path d="M8 4h8v4a4 4 0 0 1-8 0z" /><path d="M8 5H5v1a3 3 0 0 0 3 3M16 5h3v1a3 3 0 0 1-3 3" /><path d="M12 12v4M9 20h6M10 20l.5-4h3l.5 4" /></Svg>
export const IconQuill = (p: P) => <Svg {...p}><path d="M4 20c6-1 9-4 12-9 1.5-2.5 2-5 2-7-2 0-4.5.5-7 2-5 3-8 6-9 12z" /><path d="M4 20l4-4M9 14h4" /></Svg>

/* ---- Actions / status ---- */
export const IconSearch = (p: P) => <Svg {...p}><circle cx="11" cy="11" r="6" /><path d="M20 20l-4.5-4.5" /></Svg>
export const IconPlus = (p: P) => <Svg {...p}><path d="M12 5v14M5 12h14" /></Svg>
export const IconSubmit = (p: P) => <Svg {...p}><path d="M12 15V4M8 8l4-4 4 4" /><path d="M5 15v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3" /></Svg>
export const IconSeal = (p: P) => <Svg {...p}><circle cx="12" cy="10" r="6" /><path d="M12 6.5l1.3 2.4 2.7.4-2 1.9.5 2.7-2.5-1.3-2.5 1.3.5-2.7-2-1.9 2.7-.4z" /><path d="M9 15.5L8 21l4-2 4 2-1-5.5" /></Svg>
export const IconGear = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="3.2" /><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5 5l2.1 2.1M16.9 16.9L19 19M19 5l-2.1 2.1M7.1 16.9L5 19" /></Svg>
export const IconBell = (p: P) => <Svg {...p}><path d="M6 10a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6z" /><path d="M10 20a2 2 0 0 0 4 0" /></Svg>
export const IconClose = (p: P) => <Svg {...p}><path d="M6 6l12 12M18 6L6 18" /></Svg>
export const IconCheck = (p: P) => <Svg {...p}><path d="M4 12.5l5 5 11-12" /></Svg>
export const IconCross = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="9" /><path d="M8.5 8.5l7 7M15.5 8.5l-7 7" /></Svg>
export const IconClock = (p: P) => <Svg {...p}><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3.5 2" /></Svg>
export const IconLock = (p: P) => <Svg {...p}><rect x="5" y="10" width="14" height="10" rx="2" /><path d="M8 10V7a4 4 0 0 1 8 0v3" /></Svg>
export const IconTrash = (p: P) => <Svg {...p}><path d="M4 7h16M9 7V5a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2M6 7l1 13a2 2 0 0 0 2 2h6a2 2 0 0 0 2-2l1-13" /></Svg>
export const IconEye = (p: P) => <Svg {...p}><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7z" /><circle cx="12" cy="12" r="3" /></Svg>
export const IconArrowLeft = (p: P) => <Svg {...p}><path d="M19 12H5M11 6l-6 6 6 6" /></Svg>
export const IconExpand = (p: P) => <Svg {...p}><path d="M14 4h6v6M20 4l-7 7M10 20H4v-6M4 20l7-7" /></Svg>
export const IconPalette = (p: P) => <Svg {...p}><path d="M12 3a9 9 0 1 0 0 18c1.5 0 2-1 1.4-2.2-.7-1.4.3-2.8 1.8-2.8H17a4 4 0 0 0 4-4c0-4.4-4-7-9-7z" /><circle cx="8" cy="10" r="1" /><circle cx="12" cy="7.5" r="1" /><circle cx="16" cy="10" r="1" /></Svg>
export const IconLedger = (p: P) => <Svg {...p}><rect x="4" y="4" width="16" height="16" rx="2" /><path d="M4 9h16M9 4v16M12.5 12.5h4M12.5 15.5h4" /></Svg>
export const IconBolt = (p: P) => <Svg {...p}><path d="M13 3L5 13h5l-1 8 8-11h-5z" /></Svg>

/* ---- Theme-switcher emblems (each theme's world in miniature) ---- */
export const EmblemGuild = (p: P) => <Svg {...p} strokeWidth={1.5}><circle cx="12" cy="12" r="7" /><path d="M12 8.2l1.1 2.1 2.4.3-1.8 1.7.5 2.4-2.2-1.2-2.2 1.2.5-2.4-1.8-1.7 2.4-.3z" /></Svg>
export const EmblemSketch = (p: P) => <Svg {...p} strokeWidth={1.7}><path d="M4 15c2-3 3 2 5-1s2 3 4-1 3 2 5-2" /><path d="M15 6l3 3-8 8-3 .5.5-3z" /></Svg>
export const EmblemGeometry = (p: P) => <Svg {...p} strokeWidth={1.5}><circle cx="9.5" cy="12" r="5" /><rect x="11" y="7" width="8" height="8" rx="2" transform="rotate(8 15 11)" /></Svg>
