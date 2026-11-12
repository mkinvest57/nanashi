import { useRef } from 'react'
import { Apple, Smartphone } from 'lucide-react'

export type Platform = 'ios' | 'android'

// Adapted from @ruixen.ui/pill-morph-tabs (21st component 7878). The selected glass plate
// uses CSS; roving focus implements arrow/Home/End keys without a motion dependency.
export function PlatformTabs({ value, onChange }: { value: Platform; onChange: (value: Platform) => void }) {
  const refs = useRef<(HTMLButtonElement | null)[]>([])
  const platforms: Platform[] = ['ios', 'android']
  return <div className="platform-tabs" role="tablist" aria-label="Votre téléphone">
    <span className={`tab-plate ${value === 'android' ? 'tab-plate-right' : ''}`} aria-hidden="true" />
    {platforms.map((platform, index) => <button type="button" key={platform}
      id={`tab-${platform}`} role="tab" aria-selected={value === platform} aria-controls={`panel-${platform}`}
      tabIndex={value === platform ? 0 : -1} ref={el => { refs.current[index] = el }}
      onClick={() => onChange(platform)} onKeyDown={event => {
        if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return
        event.preventDefault()
        const next = event.key === 'Home' ? 0 : event.key === 'End' ? 1 : (index + 1) % 2
        onChange(platforms[next]); refs.current[next]?.focus()
      }}>
      {platform === 'ios' ? <Apple aria-hidden="true" size={19} /> : <Smartphone aria-hidden="true" size={19} />}
      {platform === 'ios' ? 'iPhone' : 'Android'}
    </button>)}
  </div>
}
