import type { AnchorHTMLAttributes, HTMLAttributes, ReactNode } from 'react'

// Adapted from @educalvolpz/glass-card and @jahed/glass-button on 21st.dev.
// Static optical layers retain the polished rim without pointer trackers or a motion runtime.
export function GlassPanel({ className = '', children, ...props }: HTMLAttributes<HTMLDivElement>) {
  return <div className={`glass-panel ${className}`} {...props}>{children}</div>
}

export function GlassLink({ className = '', children, ...props }: AnchorHTMLAttributes<HTMLAnchorElement>) {
  return <a className={`glass-link ${className}`} {...props}><span>{children}</span></a>
}

export function Eyebrow({ children }: { children: ReactNode }) {
  return <p className="eyebrow">{children}</p>
}
