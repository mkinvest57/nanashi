// Adapted from Feature 11 by Mohammad Shehadeh / Hirael (MIT).
// https://21st.dev/@mohammadshehadeh/components/feature-11
// Native tabs replace the registry's Radix wrapper; previews are real Nanashi demo captures.
import { useEffect, useRef, useState } from 'react'
import { ArrowUpRight, HeartPulse, MoonStar, Sparkles } from 'lucide-react'

const experiences = [
  {
    id: 'jour', icon: HeartPulse, label: '01', title: 'Comprenez votre journée.', short: 'Jour & activité',
    summary: 'Récupération, effort, repos. Vos repères se lisent ensemble.',
    heading: 'Un coup d’œil. Une direction.',
    detail: 'Retrouvez vos scores, vos séances et vos tendances pour décider comment aborder votre journée.',
    image: '/app-preview.jpg', alt: 'Écran Jour de Nanashi avec des scores et un historique de démonstration',
    tags: ['Récupération', 'Séances', 'Tendances'],
  },
  {
    id: 'sommeil', icon: MoonStar, label: '02', title: 'Vos nuits ont une histoire.', short: 'Sommeil & historique',
    summary: 'Remontez le fil de vos nuits et comparez ce qui change.',
    heading: 'Au-delà d’un nombre d’heures.',
    detail: 'Durée, horaires et stades estimés : votre sommeil retrouve son contexte. Sur iPhone, comparez aussi deux nuits côte à côte.',
    image: '/app-sleep.jpg', alt: 'Écran Sommeil de Nanashi avec une nuit de démonstration et ses stades estimés',
    tags: ['Chronologie', 'Comparaison', 'Historique'],
  },
  {
    id: 'coach', icon: Sparkles, label: '03', title: 'Posez la vraie question.', short: 'Coach personnel',
    summary: 'Une conversation qui part de vos propres mesures.',
    heading: 'Des données à la discussion.',
    detail: 'Interrogez votre Coach sur votre sommeil ou votre activité. Choisissez votre fournisseur IA et le contexte que vous partagez.',
    image: '/app-coach.jpg', alt: 'Écran Coach de Nanashi montrant une conversation fictive de démonstration',
    tags: ['Votre contexte', 'Votre fournisseur', 'À votre demande'],
  },
] as const

export function ProductExperience() {
  const [selected, setSelected] = useState(0)
  const [horizontal, setHorizontal] = useState(() => matchMedia('(max-width: 900px)').matches)
  const buttons = useRef<(HTMLButtonElement | null)[]>([])
  useEffect(() => {
    const media = matchMedia('(max-width: 900px)')
    const update = () => setHorizontal(media.matches)
    media.addEventListener('change', update)
    return () => media.removeEventListener('change', update)
  }, [])
  const current = experiences[selected]
  return <section className="mkt-experience mkt-section mkt-width" id="experience" aria-labelledby="experience-title">
    <div className="mkt-section-head"><div><p className="mkt-kicker">À L’INTÉRIEUR DE NANASHI</p><h2 id="experience-title">Les signaux deviennent<br /><span>des repères.</span></h2></div><p>Explorez trois façons de mieux<br className="mkt-desktop" /> lire votre quotidien.</p></div>
    <div className="mkt-experience-layout">
      <div className="mkt-feature-tabs" role="tablist" aria-label="Explorer les fonctions de Nanashi" aria-orientation={horizontal ? 'horizontal' : 'vertical'}>
        {experiences.map((item, index) => <button key={item.id} type="button" role="tab" id={`experience-tab-${item.id}`} aria-controls={`experience-panel-${item.id}`} aria-selected={selected === index} tabIndex={selected === index ? 0 : -1} ref={element => { buttons.current[index] = element }} onClick={() => setSelected(index)} onKeyDown={event => {
          let next = selected
          if (['ArrowDown', 'ArrowRight'].includes(event.key)) next = (selected + 1) % experiences.length
          else if (['ArrowUp', 'ArrowLeft'].includes(event.key)) next = (selected + experiences.length - 1) % experiences.length
          else if (event.key === 'Home') next = 0
          else if (event.key === 'End') next = experiences.length - 1
          else return
          event.preventDefault(); setSelected(next); buttons.current[next]?.focus()
        }}><span className="mkt-tab-number">{item.label}</span><span className="mkt-tab-body"><span className="mkt-tab-label"><item.icon size={20} aria-hidden="true" />{item.short}</span><strong>{item.title}</strong><span>{item.summary}</span></span><ArrowUpRight size={18} className="mkt-tab-arrow" aria-hidden="true" /></button>)}
      </div>
      <div className="mkt-experience-panel" id={`experience-panel-${current.id}`} role="tabpanel" aria-labelledby={`experience-tab-${current.id}`} tabIndex={0}>
        <div className="mkt-preview-copy"><p className="mkt-kicker">{current.short}</p><h3>{current.heading}</h3><p>{current.detail}</p><div className="mkt-preview-tags">{current.tags.map(tag => <span key={tag}>{tag}</span>)}</div>{selected === 2 && <p className="mkt-small">IA optionnelle · clé API personnelle · coûts du fournisseur éventuels.</p>}</div>
        <figure className="mkt-feature-phone"><div className="mkt-device"><img key={current.id} src={current.image} alt={current.alt} width="600" height="1299" loading="lazy" /></div><figcaption>Aperçu iPhone · données de démonstration</figcaption></figure>
      </div>
    </div>
  </section>
}
