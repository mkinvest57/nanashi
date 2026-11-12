import { useEffect, useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, Check, ChevronDown, Smartphone, Wifi } from 'lucide-react'
import { GlassLink, GlassPanel } from './Glass'
import { altStoreInstallURL, detectPhonePlatform } from '../lib/installation'
import { SETUP_LINKS } from '../lib/sidestoreSetup'
import { useCatalogue } from '../lib/useCatalogue'
import { INSTALLER_RELEASE } from '../lib/installerRelease'
import '../sidestore-setup.css'

const steps = [
  { id: 'computer', title: 'Un installateur, pour commencer', short: 'Ordinateur' },
  { id: 'iphone', title: 'Autoriser AltStore', short: 'Autoriser' },
  { id: 'remote', title: 'Activer la connexion locale', short: 'Connexion' },
  { id: 'nanashi', title: 'Installer Nanashi', short: 'Nanashi' },
  { id: 'refresh', title: 'Garder Nanashi disponible', short: 'Renouveler' },
] as const
const handoffURL = 'https://nanashi-mk.vercel.app/installation-nanashi?step=iphone#installation-etape'
const progressKey = 'nanashi.installer.handoff.v1'

function initialStep() {
  const requested = new URLSearchParams(window.location.search).get('step')
  const fromURL = steps.findIndex(step => step.id === requested)
  if (fromURL >= 0) return fromURL
  try { return Math.max(0, steps.findIndex(step => step.id === localStorage.getItem(progressKey))) }
  catch { return 0 }
}

/** This handoff confirms instructions only, never native installation success. */
export default function NanashiSetup() {
  const [index, setIndex] = useState(initialStep)
  const [computer, setComputer] = useState<'mac' | 'windows'>(() => /Win/.test(navigator.userAgent) ? 'windows' : 'mac')
  const heading = useRef<HTMLHeadingElement>(null)
  const previousIndex = useRef(index)
  const focusFromLink = useRef(new URLSearchParams(window.location.search).has('step'))
  const phone = detectPhonePlatform(navigator)
  const { state, retry } = useCatalogue()
  const release = state.status === 'ready' ? state.data.latest?.ios : null
  const installURL = release ? altStoreInstallURL(release.downloadURL) : null
  const [opened, setOpened] = useState(false)
  const [confirmed, setConfirmed] = useState(false)
  const current = steps[index]
  useEffect(() => {
    const url = new URL(window.location.href)
    if (url.searchParams.has('step')) { url.searchParams.delete('step'); history.replaceState(history.state, '', url) }
  }, [])
  useEffect(() => { try { localStorage.setItem(progressKey, current.id) } catch { /* Navigation works without browser storage. */ } }, [current.id])
  useEffect(() => {
    if (previousIndex.current !== index || focusFromLink.current) heading.current?.focus()
    previousIndex.current = index
    focusFromLink.current = false
  }, [index])

  return <div className="ss-page">
    <a className="skip-link" href="#installation-etape">Aller à l’étape en cours</a>
    <header className="ss-header ss-shell"><a className="brand" href="/"><img src="/icon.png" alt="" width="36" height="36" />Nanashi<span className="brand-dot">.</span></a><a className="quiet-link" href="/#installer"><ArrowLeft size={16} aria-hidden="true" />Retour au site</a></header>
    <main className="ss-shell">
      <div className="ss-intro"><p className="eyebrow">Votre Nanashi, étape par étape</p><h1>Un seul point de départ.</h1><p>L’installateur Nanashi prépare AltStore Classic 2.3.3. Voici les confirmations à faire sur l’iPhone, puis le bouton pour installer Nanashi.</p><p className="ss-prerequisites">iOS 17.4 minimum · même compte Apple · Wi-Fi</p></div>
      {current.id !== 'computer' && phone !== 'ios' && <section className="ss-handoff ss-prepare-handoff" aria-labelledby="nanashi-handoff"><img src="/nanashi-iphone-qr.svg" width="168" height="168" alt="QR code pour continuer l’installation Nanashi sur l’iPhone" /><div><h3 id="nanashi-handoff">Ouvrez ce site sur votre iPhone pour continuer</h3><p>Scannez ce code avec l’appareil photo de l’iPhone. Gardez cette page ouverte entre les confirmations.</p><a className="ss-share-url" href={handoffURL}>Ouvrir cette étape sur l’iPhone</a></div></section>}
      <div className="ss-layout">
        <aside className="ss-sidebar"><div className="ss-progress-heading"><span>Étape {index + 1} sur {steps.length}</span></div><nav className="ss-step-nav" aria-label="Terminer l’installation Nanashi">{steps.map((step, n) => <button type="button" key={step.id} aria-label={step.title} aria-current={n === index ? 'step' : undefined} onClick={() => setIndex(n)}><span className="ss-step-marker" aria-hidden="true">{n + 1}</span><span className="ss-step-label">{step.short}</span></button>)}</nav></aside>
        <GlassPanel className="ss-stage" aria-labelledby="installation-etape">
          <div className="ss-device-label"><Smartphone size={16} aria-hidden="true" />{current.id === 'computer' ? 'Sur votre ordinateur' : 'Sur votre iPhone'}</div><h2 id="installation-etape" ref={heading} tabIndex={-1}>{current.title}</h2>
          {current.id === 'computer' && <div className="ss-content">
            <p><strong>Nanashi Installer</strong> prépare AltStore Classic et son association à l’iPhone. Vous n’avez pas à choisir un serveur ou à exporter un fichier d’association.</p>
            {phone === 'ios' && <div className="ss-checkpoint"><Smartphone size={20} aria-hidden="true" /><p>Pour cette première préparation, ouvrez <strong>nanashi-mk.vercel.app/installation-nanashi</strong> sur votre Mac ou PC. Vous reviendrez ici en scannant le QR code de l’installateur.</p></div>}
            <div className="ss-computer-choice" role="group" aria-label="Votre ordinateur"><button type="button" aria-pressed={computer === 'mac'} onClick={() => setComputer('mac')}>Mac</button><button type="button" aria-pressed={computer === 'windows'} onClick={() => setComputer('windows')}>Windows</button></div>
            {INSTALLER_RELEASE ? <><GlassLink className="primary" href={INSTALLER_RELEASE[computer].url}>Télécharger Nanashi pour {computer === 'mac' ? 'Mac' : 'Windows'}<ArrowRight size={16} aria-hidden="true" /></GlassLink><p className="ss-caption">Installateur {INSTALLER_RELEASE.version} · version de prévisualisation. Validation complète sur iPhone encore nécessaire.</p></> : <p className="ss-note" role="status">Les paquets de l’installateur sont en cours de validation. Aucun téléchargement non vérifié n’est proposé.</p>}
            <ol className="ss-instructions"><li>Ouvrez l’installateur Nanashi sur l’ordinateur.</li><li>Branchez l’iPhone déverrouillé et suivez les écrans : iPhone, compte Apple, préparation.</li><li>Quand le QR code apparaît, scannez-le avec l’iPhone pour poursuivre directement ici.</li></ol>
            <details className="ss-help"><summary>L’ordinateur demande une confirmation ?<ChevronDown size={16} aria-hidden="true" /></summary><div><p>Le paquet de prévisualisation n’a pas de certificat commercial de distribution. Vérifiez qu’il vient de la publication Nanashi liée ici. Sur Mac, après une première tentative d’ouverture, Réglages Système → Confidentialité et sécurité peut proposer « Ouvrir quand même ».</p>{INSTALLER_RELEASE && <p><a href={INSTALLER_RELEASE.releaseURL} target="_blank" rel="noopener noreferrer">Voir la publication et les empreintes des fichiers</a></p>}<p>Ne désactivez pas les protections globales de l’ordinateur. Sur Windows, installez <a href={SETUP_LINKS.appleDevices} target="_blank" rel="noopener noreferrer">Appareils Apple</a> si la détection USB ne fonctionne pas.</p></div></details>
          </div>}
          {current.id === 'iphone' && <div className="ss-content"><p>Ces réglages sont nécessaires seulement s’ils ne sont pas déjà activés.</p><ol className="ss-instructions"><li>Réglages → Général → VPN et gestion de l’appareil → profil de votre compte Apple → <strong>Faire confiance</strong>.</li><li>Réglages → Confidentialité et sécurité → <strong>Mode développeur</strong>. Activez-le et confirmez après le redémarrage si demandé.</li><li>Ouvrez <strong>AltStore Classic</strong> sur l’iPhone.</li></ol><p className="ss-note">Gardez votre Nanashi actuelle. Ne supprimez aucune app pour terminer ces réglages.</p></div>}
          {current.id === 'remote' && <div className="ss-content"><ol className="ss-instructions"><li>Installez <strong>LocalDevVPN</strong>, ouvrez-la et touchez <strong>Connect</strong>. Autorisez la configuration VPN.<GlassLink href={SETUP_LINKS.localDevVPN} className="primary">Obtenir LocalDevVPN<ArrowRight size={16} aria-hidden="true" /></GlassLink></li><li>Dans AltStore → Settings, touchez <strong>Set up Remote AltServer…</strong> si l’assistant est proposé. Suivez ses confirmations ; l’installateur a préparé l’association avec ce téléphone.</li><li>Connectez-vous dans AltStore avec <strong>le même compte Apple que dans l’installateur Nanashi</strong>. Confirmez le code Apple si demandé.</li></ol><div className="ss-checkpoint"><Wifi size={20} aria-hidden="true" /><p>Pour installer et renouveler sans l’ordinateur : iPhone connecté au <strong>Wi-Fi</strong> et LocalDevVPN sur <strong>Connected</strong>.</p></div><details className="ss-help"><summary>Une erreur ou une demande de certificat ?<ChevronDown size={16} aria-hidden="true" /></summary><div><p>Vérifiez la version 2.3.3 dans AltStore et la connexion Wi-Fi/VPN. Si Apple refuse toujours la connexion, conservez le code exact et évitez les tentatives en boucle.</p><p>Si AltStore demande d’importer ou de révoquer un certificat, arrêtez cette étape. Ne révoquez pas le certificat qui signe vos apps existantes.</p></div></details></div>}
          {current.id === 'nanashi' && <div className="ss-content"><p>Nanashi est téléchargée depuis sa publication officielle, puis signée par AltStore sur votre iPhone.</p>{state.status === 'loading' && <p role="status">Vérification de la version disponible…</p>}{state.status === 'error' && <p role="alert">Le catalogue est indisponible. <button type="button" className="text-button" onClick={retry}>Réessayer</button></p>}{state.status === 'ready' && !release && <p>Aucune version iPhone n’est publiée dans le catalogue pour le moment.</p>}{installURL && (phone === 'ios' ? <GlassLink className="primary" href={installURL} onClick={() => setOpened(true)}>Installer Nanashi avec AltStore<ArrowRight size={16} aria-hidden="true" /></GlassLink> : <p className="ss-note">Ouvrez cette page sur l’iPhone avec le QR code pour afficher le bouton d’installation.</p>)}{opened && <p className="ss-checkpoint" role="status">Dans AltStore, confirmez l’installation. Conservez le widget si proposé, puis attendez la fin.</p>}<p className="ss-note">Pour une mise à jour, faites une sauvegarde récente dans Nanashi, gardez le même compte Apple et laissez la randomisation des identifiants désactivée dans AltStore. Si une seconde copie apparaît, conservez l’ancienne : son historique n’est pas transféré automatiquement.</p><p>Quand Nanashi s’ouvre et que votre historique est visible, continuez.</p></div>}
          {current.id === 'refresh' && <div className="ss-content"><p>AltStore possède son propre renouvellement en arrière-plan. Vous n’avez pas à recréer le raccourci SideStore pour ce parcours.</p><ol className="ss-instructions"><li>Dans AltStore → Settings, activez <strong>Background Refresh</strong>. Dans Réglages iPhone → Général → <strong>Actualisation en arrière-plan</strong>, autorisez aussi AltStore.</li><li>Laissez <strong>LocalDevVPN actif</strong> et connectez régulièrement l’iPhone au Wi-Fi.</li><li>Dans AltStore → My Apps, lancez <strong>Refresh All</strong> une fois et vérifiez les compteurs.</li></ol><p className="ss-note">iOS décide des exécutions en arrière-plan : l’heure de renouvellement n’est pas garantie. Si un compteur approche de zéro, ouvrez AltStore et renouvelez manuellement. Le compte gratuit conserve une validité de 7 jours.</p><details className="ss-help"><summary>Vous aviez une automatisation SideStore ?<ChevronDown size={16} aria-hidden="true" /></summary><div><p>Elle cible SideStore, pas AltStore. Ne la considérez pas comme une preuve du renouvellement de cette installation. Gardez vos anciennes apps et leur configuration pendant la vérification de la nouvelle copie.</p></div></details>{confirmed && <p role="status" className="ss-complete"><Check size={17} aria-hidden="true" />Vous avez confirmé la fin du parcours.</p>}</div>}
          <div className="ss-actions">{index > 0 && <button type="button" className="ss-back" onClick={() => setIndex(n => n - 1)}><ArrowLeft size={16} aria-hidden="true" />Retour</button>}{index < steps.length - 1 ? <button type="button" className="glass-link primary ss-continue" onClick={() => setIndex(n => n + 1)}><span>C’est fait, continuer<ArrowRight size={16} aria-hidden="true" /></span></button> : !confirmed && <button type="button" className="glass-link primary ss-continue" onClick={() => setConfirmed(true)}><span>J’ai vérifié le renouvellement<Check size={16} aria-hidden="true" /></span></button>}</div>
        </GlassPanel>
      </div>
    </main><footer className="ss-footer ss-shell"><p>Aucun identifiant Apple ni donnée de santé n’est demandé sur ce site.</p><a href="/">Retour à Nanashi</a></footer>
  </div>
}
