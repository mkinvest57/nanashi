import { useEffect, useRef, useState } from 'react'
import type { ReactNode } from 'react'
import { ArrowLeft, ArrowRight, Check, ChevronDown, Copy, Download, Laptop, RotateCcw, Smartphone } from 'lucide-react'
import { GlassLink, GlassPanel } from './Glass'
import { detectPhonePlatform } from '../lib/installation'
import {
  initialSetupProgress, readSetupProgress, saveSetupProgress, setupProgressFromURL, SETUP_AUTOMATION_URL, SETUP_GUIDE_URL, SETUP_IPHONE_URL, SETUP_LINKS, SETUP_STEPS,
} from '../lib/sidestoreSetup'
import type { SetupComputer, StepId } from '../lib/sidestoreSetup'
import '../sidestore-setup.css'

function browserStorage(): Storage | null {
  try { return window.localStorage } catch { return null }
}

function Help({ title, children }: { title: string; children: ReactNode }) {
  return <details className="ss-help"><summary>{title}<ChevronDown size={16} aria-hidden="true" /></summary><div>{children}</div></details>
}

function DownloadLink({ href, children, primary = true }: { href: string; children: ReactNode; primary?: boolean }) {
  return <GlassLink href={href} target="_blank" rel="noopener noreferrer" className={primary ? 'primary' : ''}>
    <Download size={17} aria-hidden="true" />{children}
  </GlassLink>
}

export default function SideStoreSetup() {
  const [progress, setProgress] = useState(() => setupProgressFromURL(
    readSetupProgress(browserStorage(), /Win/.test(navigator.userAgent) ? 'windows' : 'mac'), window.location.search))
  const [saved, setSaved] = useState(true)
  const [copyStatus, setCopyStatus] = useState('')
  const [phoneCopyStatus, setPhoneCopyStatus] = useState('')
  const headingRef = useRef<HTMLHeadingElement>(null)
  const shouldFocus = useRef(new URLSearchParams(window.location.search).get('step') === progress.step)
  const phone = detectPhonePlatform(navigator)
  const index = SETUP_STEPS.findIndex(step => step.id === progress.step)
  const current = SETUP_STEPS[index]
  const isComputerStep = index < 3
  const computerName = progress.computer === 'mac' ? 'Mac' : 'PC Windows'
  const allConfirmed = progress.confirmed.length === SETUP_STEPS.length

  useEffect(() => { setSaved(saveSetupProgress(browserStorage(), progress)) }, [progress])
  useEffect(() => {
    const url = new URL(window.location.href)
    if (url.searchParams.has('step')) {
      url.searchParams.delete('step')
      window.history.replaceState(window.history.state, '', url)
    }
  }, [])
  useEffect(() => {
    if (shouldFocus.current) {
      headingRef.current?.focus()
      shouldFocus.current = false
    }
  }, [progress.step])

  function goTo(step: StepId) {
    if (step === progress.step) { headingRef.current?.focus(); return }
    shouldFocus.current = true
    setProgress(value => ({ ...value, step }))
  }

  function continueGuide() {
    shouldFocus.current = index < SETUP_STEPS.length - 1
    setProgress(value => ({
      ...value,
      step: SETUP_STEPS[Math.min(index + 1, SETUP_STEPS.length - 1)].id,
      confirmed: [...new Set([...value.confirmed, value.step])],
    }))
  }

  function resetGuide() {
    shouldFocus.current = progress.step !== 'computer'
    setProgress(initialSetupProgress(progress.computer))
    if (progress.step === 'computer') headingRef.current?.focus()
  }

  function finishGuide() {
    setProgress(value => ({ ...value, confirmed: SETUP_STEPS.map(step => step.id) }))
  }

  function chooseComputer(computer: SetupComputer) {
    setProgress(value => ({ ...value, computer }))
  }

  async function copyGuide() {
    try {
      await navigator.clipboard.writeText(SETUP_GUIDE_URL)
      setCopyStatus('Lien copié.')
    } catch { setCopyStatus('La copie est indisponible. Vous pouvez sélectionner le lien ci-dessous.') }
  }

  async function copyPhoneStep() {
    try {
      await navigator.clipboard.writeText(SETUP_IPHONE_URL)
      setPhoneCopyStatus('Lien vers cette étape copié.')
    } catch { setPhoneCopyStatus('Vous pouvez copier l’adresse du lien ci-dessous.') }
  }

  return <div className="ss-page">
    <a className="skip-link" href="#setup-step-heading">Aller à l’étape en cours</a>
    <header className="ss-header ss-shell">
      <a className="brand" href="/" aria-label="Nanashi, accueil"><img src="/icon.png" alt="" width="36" height="36" />Nanashi<span className="brand-dot">.</span></a>
      <a className="quiet-link" href="/#installer"><ArrowLeft size={16} aria-hidden="true" />Retour à Nanashi</a>
    </header>

    <main className="ss-shell">
      <div className="ss-intro">
        <p className="eyebrow">Votre iPhone, votre Nanashi</p>
        <h1>Installation SideStore</h1>
        <p>Une préparation initiale avec un ordinateur. Ensuite, vous pourrez installer et renouveler Nanashi depuis votre iPhone.</p>
        <p className="ss-prerequisites">À prévoir : un compte Apple gratuit, un câble USB et un réseau Wi-Fi.</p>
        <a className="text-link" href="/#installer">SideStore fonctionne déjà ? Aller à Nanashi<ArrowRight size={15} aria-hidden="true" /></a>
      </div>

      <div className="ss-layout">
        <aside className="ss-sidebar">
          <div className="ss-progress-heading"><span>Étape {index + 1} sur {SETUP_STEPS.length}</span><span>{progress.confirmed.length} confirmée{progress.confirmed.length > 1 ? 's' : ''}</span></div>
          <progress className="ss-progress" max={SETUP_STEPS.length} value={progress.confirmed.length} aria-label="Étapes confirmées" />
          <nav aria-label="Étapes de l’installation" className="ss-step-nav">
            {SETUP_STEPS.map((step, stepIndex) => <button key={step.id} type="button"
              onClick={() => goTo(step.id)} aria-label={`Étape ${stepIndex + 1} : ${step.title}`}
              aria-current={step.id === progress.step ? 'step' : undefined}
              className={progress.confirmed.includes(step.id) ? 'ss-confirmed' : ''}>
              <span className="ss-step-marker" aria-hidden="true">{progress.confirmed.includes(step.id) ? <Check size={15} /> : stepIndex + 1}</span>
              <span className="ss-step-label">{step.short}</span>
            </button>)}
          </nav>
        </aside>

        <GlassPanel className="ss-stage" aria-labelledby="setup-step-heading">
          <div className="ss-device-label">{isComputerStep ? <Laptop size={16} aria-hidden="true" /> : <Smartphone size={16} aria-hidden="true" />}
            {isComputerStep ? `Sur votre ${computerName}` : 'Sur votre iPhone'}</div>
          <h2 id="setup-step-heading" tabIndex={-1} ref={headingRef}>{current.title}</h2>

          {current.id === 'computer' && <div className="ss-content">
            <p>iloader installe SideStore sur l’iPhone. Choisissez l’ordinateur que vous allez utiliser.</p>
            <div className="ss-computer-choice" role="group" aria-label="Votre ordinateur">
              <button type="button" aria-pressed={progress.computer === 'mac'} onClick={() => chooseComputer('mac')}>Mac</button>
              <button type="button" aria-pressed={progress.computer === 'windows'} onClick={() => chooseComputer('windows')}>Windows</button>
            </div>
            {progress.computer === 'mac' ? <>
              <DownloadLink href={SETUP_LINKS.mac}>Télécharger iloader pour Mac</DownloadLink>
              <p className="ss-caption">Un seul téléchargement pour les Mac Intel et Apple Silicon.</p>
              <ol className="ss-instructions"><li>Ouvrez le fichier téléchargé.</li><li>Glissez <strong>iloader</strong> dans <strong>Applications</strong>, puis ouvrez-le.</li></ol>
              <Help title="Le Mac empêche l’ouverture ?"><p>Après avoir tenté d’ouvrir iloader, allez dans Réglages Système → Confidentialité et sécurité. Si macOS propose « Ouvrir quand même » pour iloader, utilisez ce bouton, puis confirmez l’ouverture.</p><p>Utilisez uniquement le téléchargement officiel proposé ici. N’abaissez pas la sécurité globale du Mac.</p><a href={SETUP_LINKS.iloaderSource} target="_blank" rel="noopener noreferrer">Voir le projet iloader officiel</a></Help>
            </> : <>
              <ol className="ss-instructions ss-download-steps">
                <li><strong>Installez iTunes.</strong><p>Il fournit les composants Apple nécessaires pour reconnaître l’iPhone.</p><DownloadLink href={SETUP_LINKS.itunes} primary={false}>Télécharger iTunes</DownloadLink></li>
                <li><strong>Installez puis ouvrez iloader.</strong><DownloadLink href={SETUP_LINKS.windows}>Télécharger iloader pour Windows</DownloadLink></li>
              </ol>
              <p className="ss-caption">Pour Windows 10 ou 11 sur un PC 64 bits Intel ou AMD.</p>
              <Help title="Un téléchargement ou la détection bloque ?"><p>Vous pouvez aussi installer <a href={SETUP_LINKS.itunesStore} target="_blank" rel="noopener noreferrer">iTunes depuis le Microsoft Store</a>. Si iTunes ne permet toujours pas de reconnaître l’iPhone, essayez <a href={SETUP_LINKS.appleDevices} target="_blank" rel="noopener noreferrer">Appareils Apple</a>, puis rouvrez iloader.</p><p>Si l’installateur MSI échoue, <a href={SETUP_LINKS.windowsExe} target="_blank" rel="noopener noreferrer">téléchargez la version EXE d’iloader</a>. Windows 32 bits et Windows 10 ARM ne sont pas pris en charge.</p></Help>
            </>}
          </div>}

          {current.id === 'connect' && <div className="ss-content">
            <p>Gardez l’iPhone déverrouillé pendant cette préparation.</p>
            <ol className="ss-instructions"><li>Vérifiez que l’iPhone utilise <strong>iOS 16 ou plus récent</strong>, avec un code de déverrouillage, et qu’il est connecté à un réseau Wi-Fi.</li><li>Branchez-le au {computerName} avec un câble USB.</li><li>Si l’iPhone demande <strong>« Faire confiance à cet ordinateur »</strong>, acceptez et saisissez son code.</li></ol>
            <div className="ss-checkpoint"><Smartphone size={20} aria-hidden="true" /><p>Vous pouvez continuer lorsque votre iPhone apparaît dans iloader.</p></div>
            <Help title="L’iPhone n’apparaît pas ?"><p>Déverrouillez-le, débranchez puis rebranchez le câble et rouvrez iloader. Essayez un autre port ou un câble qui transporte des données, pas uniquement la charge.</p>{progress.computer === 'windows' && <p>Vérifiez aussi qu’iTunes reconnaît l’iPhone. Les liens Apple sont disponibles à l’étape « Ordinateur ».</p>}</Help>
          </div>}

          {current.id === 'install' && <div className="ss-content">
            <p>Tout se passe maintenant dans la fenêtre iloader.</p>
            <ol className="ss-instructions"><li>Sélectionnez votre iPhone.</li><li>Connectez-vous avec votre <strong>compte Apple</strong> et terminez la validation à deux facteurs si elle apparaît.</li><li>Dans <strong>Installateurs</strong>, choisissez <strong>« SideStore (Stable) »</strong>, puis attendez la fin de l’installation.</li></ol>
            <p className="ss-note">Saisissez vos identifiants dans iloader, jamais sur cette page. Vous utiliserez le même compte dans SideStore.</p>
            <Help title="iloader signale une erreur ?"><p>Laissez l’iPhone déverrouillé et vérifiez qu’il est toujours sélectionné. Si la connexion Apple échoue, terminez les éventuelles demandes de validation sur vos appareils Apple avant de réessayer.</p><p>iloader prépare automatiquement les fichiers d’association et le certificat. Vous n’avez pas à exporter un fichier d’association pour cette installation normale.</p><p>Si un avertissement propose de révoquer un certificat déjà utilisé, ne le validez pas à l’aveugle : les autres apps signées avec ce certificat peuvent cesser de s’ouvrir.</p></Help>
          </div>}

          {current.id === 'prepare' && <div className="ss-content">
            {phone === 'ios' ? <div className="ss-checkpoint"><Smartphone size={20} aria-hidden="true" /><p>Vous avez ouvert le guide sur votre iPhone. Suivez les réglages ci-dessous, puis revenez ici pour continuer.</p></div>
              : <section className="ss-handoff ss-prepare-handoff" aria-labelledby="ss-iphone-handoff-title">
                <img src="/sidestore-iphone-qr.svg" alt="QR code pour ouvrir l’étape Préparer l’iPhone sur votre iPhone" width="168" height="168" />
                <div><h3 id="ss-iphone-handoff-title">Ouvrez maintenant ce site sur votre iPhone</h3>
                  <p>Scannez ce QR code avec l’appareil photo de l’iPhone, puis touchez le lien affiché. Le guide s’ouvrira directement à cette étape pour continuer.</p>
                  <button className="text-button" type="button" onClick={copyPhoneStep}><Copy size={15} aria-hidden="true" />Copier le lien de cette étape</button>
                  <p className="ss-copy-status" role="status">{phoneCopyStatus}</p>
                  <a className="ss-share-url" href={SETUP_IPHONE_URL}>Ouvrir cette étape sur l’iPhone</a>
                </div>
              </section>}
            <p>Autorisez SideStore, puis préparez sa connexion locale.</p>
            <ol className="ss-instructions">
              <li><strong>Faites confiance au développeur.</strong><p>Réglages → Général → VPN et gestion de l’appareil → le profil de votre compte Apple → Faire confiance. Si iOS propose « Autoriser et redémarrer », suivez cette demande.</p></li>
              <li><strong>Activez le Mode développeur.</strong><p>Réglages → Confidentialité et sécurité → Mode développeur. Redémarrez si demandé, puis confirmez « Activer » sur l’iPhone. Si ce mode est déjà actif, passez à la suite.</p></li>
              <li><strong>Installez et ouvrez LocalDevVPN.</strong><p>Autorisez sa configuration VPN, puis touchez « Connect ». Attendez l’état <strong>Connected</strong>.</p><DownloadLink href={SETUP_LINKS.localDevVPN}>Obtenir LocalDevVPN</DownloadLink></li>
            </ol>
            <p className="ss-caption">LocalDevVPN est l’app gratuite de Coxson Engineering. Gardez aussi l’iPhone connecté à un réseau Wi-Fi.</p>
            <Help title="Un réglage n’apparaît pas ?"><p>Le profil développeur et le Mode développeur peuvent n’apparaître qu’après l’installation de SideStore. Revenez à l’étape précédente si l’installation n’est pas terminée.</p><p>Si LocalDevVPN ne reste pas connecté, vérifiez qu’un autre VPN n’a pas repris la connexion, puis rouvrez LocalDevVPN.</p></Help>
          </div>}

          {current.id === 'activate' && <div className="ss-content">
            <p>Ce premier renouvellement permet à SideStore de gérer les prochaines installations.</p>
            <ol className="ss-instructions"><li>Vérifiez <strong>iPhone connecté à un réseau Wi-Fi</strong> et <strong>LocalDevVPN → Connected</strong>.</li><li>Ouvrez SideStore et connectez-vous avec <strong>le même compte Apple que dans iloader</strong>.</li><li>Dans <strong>My Apps</strong>, touchez le compteur <strong>DAYS</strong> à côté de SideStore. Attendez la fin du renouvellement.</li><li>Si SideStore vous ramène à l’écran d’accueil, rouvrez-la.</li></ol>
            <div className="ss-checkpoint"><Check size={20} aria-hidden="true" /><p>Continuez après un renouvellement réussi et la réouverture de SideStore.</p></div>
            <Help title="La connexion ou le renouvellement échoue ?"><p>Vérifiez d’abord la connexion à un réseau Wi-Fi, l’état Connected de LocalDevVPN et le compte Apple utilisé. Fermez puis rouvrez SideStore et réessayez une fois.</p><p>Si l’erreur persiste, conservez son code exact. Ne désinstallez pas vos apps et ne réinitialisez pas leurs données pour contourner une erreur de connexion.</p></Help>
          </div>}

          {current.id === 'nanashi' && <div className="ss-content">
            <p>Ouvrez maintenant la page Nanashi sur l’iPhone. Choisissez <strong>« J’ai déjà SideStore »</strong>, puis <strong>« Installer / mettre à jour Nanashi »</strong>.</p>
            <GlassLink href="/#installer" className="primary">Installer Nanashi<ArrowRight size={17} aria-hidden="true" /></GlassLink>
            <ol className="ss-instructions"><li>Gardez l’iPhone connecté au Wi-Fi et LocalDevVPN actif.</li><li>Dans SideStore, validez <strong>Install</strong>.</li><li>Si le choix du widget apparaît, sélectionnez <strong lang="en">Keep App Extensions (Register App ID for Each Extension)</strong>.</li></ol>
            <Help title="Nanashi est déjà installée sur cet iPhone ?"><p>Ne désinstallez pas Nanashi. Faites d’abord une sauvegarde récente depuis l’app et mettez à jour la copie existante avec le même compte SideStore. Si une deuxième copie apparaît, n’effacez pas l’ancienne : son historique n’est pas automatiquement transféré.</p></Help>
            <p className="ss-note">Une fois Nanashi installée, continuez : la dernière étape ajoute le raccourci de renouvellement.</p>
          </div>}

          {current.id === 'automation' && <div className="ss-content">
            <p>Ajoutez le raccourci prêt à l’emploi. Il active <strong>LocalDevVPN</strong>, attend <strong>5 secondes</strong>, puis demande à SideStore de <strong>renouveler toutes les apps</strong>, dont Nanashi.</p>
            {phone !== 'ios' && <section className="ss-handoff ss-prepare-handoff ss-shortcut-handoff" aria-labelledby="ss-shortcut-handoff-title">
              <img src="/sidestore-automation-qr.svg" alt="QR code pour ouvrir l’installation du raccourci sur l’iPhone" width="168" height="168" />
              <div><h3 id="ss-shortcut-handoff-title">Installez le raccourci sur votre iPhone</h3><p>Scannez ce code avec l’iPhone pour retrouver cette dernière étape et son bouton d’installation.</p><a className="ss-share-url" href={SETUP_AUTOMATION_URL}>Ouvrir cette étape sur l’iPhone</a></div>
            </section>}
            <GlassLink href={SETUP_LINKS.shortcut} className="primary">Installer le raccourci<Download size={17} aria-hidden="true" /></GlassLink>
            <p className="ss-caption">Le lien Apple ouvre <strong>Refresh All Apps</strong>. Confirmez « Ajouter le raccourci » dans Raccourcis. Aucun identifiant Apple n’est demandé sur ce site.</p>
            <ol className="ss-instructions">
              <li><strong>Essayez-le une fois.</strong><p>Avec l’iPhone connecté au Wi-Fi, lancez le raccourci ajouté et acceptez les autorisations demandées. Vérifiez dans SideStore → My Apps que les compteurs ont été renouvelés.</p></li>
              <li><strong>Confirmez le renouvellement quotidien.</strong><p>Dans Raccourcis, vérifiez l’horaire de l’automatisation importée, choisissez <strong>Tous les jours</strong> et <strong>Exécuter immédiatement</strong>, puis activez-la. Choisissez une heure où l’iPhone est sur le Wi-Fi, par exemple <strong>9 h</strong>.</p></li>
            </ol>
            <Help title="SideStore affiche une action inconnue ?"><p>Sur un autre compte Apple, iOS peut ne pas reconnaître l’action SideStore du raccourci partagé. Il suffit de remplacer cette action une fois :</p><ol><li>Ouvrez le raccourci <strong>Refresh All Apps</strong> avec le bouton <strong>…</strong>.</li><li>Supprimez uniquement l’action SideStore non reconnue, en laissant LocalDevVPN et l’attente de 5 secondes.</li><li>Recherchez <strong>SideStore</strong> dans les actions et ajoutez <strong>Refresh All Apps</strong> à la fin. Enregistrez, puis réessayez.</li></ol><p>Si l’action n’est pas proposée, ouvrez d’abord SideStore et terminez son premier renouvellement, puis revenez dans Raccourcis.</p></Help>
            <Help title="Aucun horaire n’apparaît ?"><p>Les anciennes versions d’iOS n’importent pas la programmation avec le raccourci. Une seule configuration est nécessaire :</p><ol><li>Dans Raccourcis → <strong>Automatisation</strong> → <strong>+</strong>, choisissez <strong>Heure de la journée</strong>.</li><li>Choisissez votre heure, <strong>Tous les jours</strong>, puis <strong>Exécuter immédiatement</strong>. Sur un ancien iOS, désactivez <strong>Demander avant d’exécuter</strong>.</li><li>Sélectionnez le raccourci <strong>Refresh All Apps</strong> que vous venez d’ajouter. Si iOS affiche un éditeur d’actions, ajoutez <strong>Exécuter le raccourci</strong> et choisissez-le.</li></ol></Help>
            <Help title="Un renouvellement est déjà configuré ?"><p>Gardez votre automatisation actuelle si elle fonctionne. N’ajoutez pas une deuxième programmation quotidienne pour la même tâche. Vous pouvez passer cette étape.</p></Help>
            <p className="ss-note">Gardez le Wi-Fi disponible à l’heure choisie. Une erreur Apple ou VPN peut encore demander de rouvrir SideStore. Le renouvellement prolonge la signature ; il ne télécharge pas les nouvelles versions de Nanashi.</p>
            {allConfirmed && <p className="ss-complete" role="status"><Check size={17} aria-hidden="true" />Guide marqué comme terminé. Vous pouvez revenir à n’importe quelle étape.</p>}
          </div>}

          <div className="ss-actions">
            {index > 0 && <button className="ss-back" type="button" onClick={() => goTo(SETUP_STEPS[index - 1].id)}><ArrowLeft size={16} aria-hidden="true" />Retour</button>}
            {index < SETUP_STEPS.length - 1
              ? <button className="glass-link primary ss-continue" type="button" onClick={continueGuide}><span>C’est fait, continuer<ArrowRight size={16} aria-hidden="true" /></span></button>
              : !allConfirmed && <button className="text-button ss-finish" type="button" onClick={finishGuide}>Marquer le guide comme terminé<Check size={16} aria-hidden="true" /></button>}
          </div>
        </GlassPanel>
        <div className="ss-save-controls">
          <p className="ss-save-note">{saved ? 'Votre progression est confirmée par vous et enregistrée uniquement dans ce navigateur.' : 'La progression reste disponible sur cette page, mais ce navigateur ne permet pas de l’enregistrer.'}</p>
          <button className="text-button ss-reset" type="button" onClick={resetGuide}><RotateCcw size={14} aria-hidden="true" />Recommencer le guide</button>
        </div>
      </div>

      {current.id !== 'prepare' && <section className="ss-handoff" aria-labelledby="ss-handoff-title">
        {!phone && <img src="/sidestore-setup-qr.svg" alt="QR code pour ouvrir ce guide sur l’iPhone" width="112" height="112" />}
        <div><h2 id="ss-handoff-title">Continuer sur un autre appareil</h2><p>{!phone ? 'Scannez ce code avec l’iPhone, ou copiez le lien. ' : 'Copiez ce lien pour retrouver le guide sur votre ordinateur. '}Sur l’autre appareil, choisissez l’étape où vous en êtes : la progression ne se synchronise pas.</p>
          <button className="text-button" type="button" onClick={copyGuide}><Copy size={15} aria-hidden="true" />Copier le lien du guide</button>
          <p className="ss-copy-status" role="status">{copyStatus}</p><a className="ss-share-url" href={SETUP_GUIDE_URL}>{SETUP_GUIDE_URL}</a>
        </div>
      </section>}
    </main>
    <footer className="ss-footer ss-shell"><div><p>Ce guide ne reçoit aucun identifiant Apple et ne collecte aucune donnée de santé.</p><a href={SETUP_LINKS.iloaderSource} target="_blank" rel="noopener noreferrer">iloader · projet officiel</a></div><a href="/">Retour au site Nanashi</a></footer>
  </div>
}
