import { useEffect, useState } from 'react'
import { ArrowDownToLine, ArrowRight, ArrowUpRight, Check, ChevronDown, Copy, ExternalLink, RefreshCw, ShieldCheck, Smartphone, Wifi } from 'lucide-react'
import { Eyebrow, GlassLink, GlassPanel } from './Glass'
import { PlatformTabs } from './PlatformTabs'
import type { Platform } from './PlatformTabs'
import { fetchCatalogue, readableSize, REPOSITORY } from '../lib/releases'
import type { Artifact, Catalogue } from '../lib/releases'
import { androidVersionLabel, detectPhonePlatform, sideStoreInstallURL } from '../lib/installation'

type CatalogueState = { status: 'loading' } | { status: 'ready'; data: Catalogue } | { status: 'error' }
type IOSPath = 'ready' | 'first'

function useCatalogue() {
  const [state, setState] = useState<CatalogueState>({ status: 'loading' })
  const [attempt, setAttempt] = useState(0)
  useEffect(() => {
    const controller = new AbortController()
    let active = true
    setState({ status: 'loading' })
    const timer = window.setTimeout(() => controller.abort(), 12_000)
    fetchCatalogue(controller.signal).then(data => {
      if (active) setState({ status: 'ready', data })
    }).catch(() => { if (active) setState({ status: 'error' }) })
      .finally(() => window.clearTimeout(timer))
    return () => { active = false; controller.abort(); window.clearTimeout(timer) }
  }, [attempt])
  return { state, retry: () => setAttempt(value => value + 1) }
}

function CopyValue({ value, label }: { value: string; label: string }) {
  const [message, setMessage] = useState('')
  useEffect(() => { setMessage('') }, [value])
  return <div className="copy-field">
    <code>{value}</code>
    <button type="button" className="icon-button" aria-label={label} onClick={async () => {
      try { await navigator.clipboard.writeText(value); setMessage('Copié') }
      catch { setMessage('Copie indisponible : sélectionnez le texte ci-dessus.') }
    }}>{message === 'Copié' ? <Check size={18} /> : <Copy size={18} />}</button>
    <span className="copy-status" role="status">{message}</span>
  </div>
}

function ArtifactDetails({ artifact }: { artifact: Artifact }) {
  return <details className="artifact-details">
    <summary>Vérifier ce téléchargement <ChevronDown size={16} aria-hidden="true" /></summary>
    <dl><div><dt>Version</dt><dd>{artifact.version} · build {artifact.build}</dd></div>
      <div><dt>Taille</dt><dd>{readableSize(artifact.size)}</dd></div></dl>
    <span className="small-label">Empreinte SHA-256</span>
    <CopyValue value={artifact.sha256} label="Copier l’empreinte SHA-256" />
  </details>
}

export function InstallSection() {
  const [phone] = useState(() => detectPhonePlatform(navigator))
  const [platform, setPlatform] = useState<Platform>(() => phone ?? 'ios')
  const [iosPath, setIOSPath] = useState<IOSPath>('ready')
  const [started, setStarted] = useState<Platform | null>(null)
  const [helpOpen, setHelpOpen] = useState(false)
  const { state, retry } = useCatalogue()
  const data = state.status === 'ready' ? state.data : null
  const release = data?.latest
  const artifact = platform === 'ios' ? release?.ios : release?.android
  const source = data?.sideStore
  const installURL = release?.ios ? sideStoreInstallURL(release.ios.downloadURL) : null
  const onPlatformChange = (next: Platform) => { setPlatform(next); setStarted(null); setHelpOpen(false) }
  const onPathChange = (next: IOSPath) => { setIOSPath(next); setStarted(null) }

  const installAction = artifact && installURL && (phone === 'ios'
    ? <GlassLink className="primary install-primary" href={installURL} onClick={() => setStarted('ios')}>
      Installer / mettre à jour Nanashi <ArrowUpRight size={18} aria-hidden="true" />
    </GlassLink>
    : phone === null ? <GlassLink className="primary install-primary" href="#ouvrir-sur-telephone">
      Continuer sur mon téléphone <Smartphone size={18} aria-hidden="true" />
    </GlassLink> : <p className="other-phone-guidance">Ouvrez cette page sur un iPhone pour installer Nanashi avec SideStore.</p>)

  return <section className="install-section section" id="installer" aria-labelledby="install-heading">
    <div className="section-heading">
      <div><Eyebrow>À vous de jouer</Eyebrow><h2 id="install-heading">Installez Nanashi.<br /><span>Gardez votre rythme.</span></h2></div>
      <p>{phone ? 'Votre app, en quelques gestes.' : <>Ouvrez cette page sur votre téléphone.<br />Le code à scanner est juste ici.</>}</p>
    </div>
    <GlassPanel className={`install-panel ${phone ? 'install-panel-phone' : ''}`}>
      <div className="install-choice">
        <PlatformTabs value={platform} onChange={onPlatformChange} />
        <div id={`panel-${platform}`} role="tabpanel" aria-labelledby={`tab-${platform}`} tabIndex={0} className="platform-panel">
          <div className="platform-heading"><img src="/icon-192.png" width="58" height="58" alt="" /><div><h3>Nanashi pour {platform === 'ios' ? 'iPhone' : 'Android'}</h3>
            <p>{artifact ? `Version ${artifact.version}` : 'Votre suivi, sur votre téléphone.'}</p></div></div>
          <div className="release-state" aria-live="polite">
            {state.status === 'loading' && <p className="muted"><RefreshCw size={16} aria-hidden="true" /> Vérification de la dernière version…</p>}
            {state.status === 'error' && <div><p>Le catalogue est momentanément inaccessible.</p><button type="button" className="text-button" onClick={retry}><RefreshCw size={16} aria-hidden="true" /> Réessayer</button></div>}
            {state.status === 'ready' && !artifact && <><span className="release-label"><span className="status-dot" /> Publication en préparation</span><p>Le téléchargement {platform === 'ios' ? 'iPhone' : 'Android'} apparaîtra dès que sa version sera publiée.</p></>}
            {artifact && <p className="compatibility">{platform === 'ios' ? `iOS ${release?.ios?.minOSVersion} ou version ultérieure` : androidVersionLabel(release!.android!.minSDK)}</p>}
          </div>

          {platform === 'ios' && <>
            <div className="setup-choice" role="group" aria-label="Votre installation SideStore">
              <button type="button" aria-pressed={iosPath === 'ready'} onClick={() => onPathChange('ready')}>J’ai déjà SideStore</button>
              <button type="button" aria-pressed={iosPath === 'first'} onClick={() => onPathChange('first')}>Première installation</button>
            </div>
            {iosPath === 'ready' ? <div className="quick-install">
              <p className="installation-instruction"><Wifi size={18} aria-hidden="true" /><span>Activez le Wi-Fi et LocalDevVPN sur l’iPhone, puis lancez l’installation.</span></p>
              {installAction}
              <p className="next-step">Dans SideStore, touchez « Install ». Gardez le widget si demandé. Ne désinstallez pas Nanashi.</p>
            </div> : <div className="first-install" aria-label="Première installation sur iPhone">
              <p className="setup-intro">Une préparation à faire une seule fois. Ensuite, ce bouton suffira pour ouvrir les prochaines mises à jour.</p>
              <details className="setup-step" open>
                <summary><span className="step-number">1</span><span>Configurer SideStore</span><ChevronDown size={16} aria-hidden="true" /></summary>
                <div><p>Sur un ordinateur, installez SideStore sur l’iPhone avec votre compte Apple. Suivez son guide, puis revenez ici.</p>
                  <GlassLink href="https://docs.sidestore.io/docs/installation/install" target="_blank" rel="noreferrer">Ouvrir le guide SideStore <ExternalLink size={16} aria-hidden="true" /></GlassLink></div>
              </details>
              <details className="setup-step">
                <summary><span className="step-number">2</span><span>Préparer l’iPhone</span><ChevronDown size={16} aria-hidden="true" /></summary>
                <div><p>Connectez l’iPhone au Wi-Fi. Ouvrez LocalDevVPN jusqu’à « Connected », puis vérifiez que SideStore est connectée à votre compte Apple.</p><p>Cette page ne peut pas vérifier ces réglages à votre place.</p></div>
              </details>
              <details className="setup-step">
                <summary><span className="step-number">3</span><span>Installer Nanashi</span><ChevronDown size={16} aria-hidden="true" /></summary>
                <div><p>Une fois SideStore prête, ouvrez l’installation puis confirmez avec « Install ». Conservez le widget si proposé.</p>{installAction}</div>
              </details>
            </div>}
          </>}

          {platform === 'android' && <div className="quick-install">
            <p className="installation-instruction"><ArrowDownToLine size={18} aria-hidden="true" /><span>Téléchargez Nanashi, puis ouvrez le fichier sur votre téléphone Android.</span></p>
            {artifact && <GlassLink className="primary install-primary" href={artifact.downloadURL} onClick={() => setStarted('android')}>Télécharger Nanashi <ArrowDownToLine size={18} aria-hidden="true" /></GlassLink>}
            <p className="next-step">Android vous demandera d’autoriser l’installation si nécessaire.</p>
          </div>}

          {started === platform && <div className="installation-followup" role="status">
            <strong>{platform === 'ios' ? 'Dans SideStore, touchez « Install ».' : 'Ouvrez le fichier téléchargé sur votre téléphone Android.'}</strong>
            <p>{platform === 'ios' ? 'Si le widget est proposé, choisissez « Keep App Extensions (Register App ID for Each Extension) ».' : 'Autorisez votre navigateur à installer Nanashi si Android le demande, puis confirmez.'}</p>
            <button type="button" className="text-button" onClick={() => setHelpOpen(true)}>{platform === 'ios' ? 'SideStore ne s’ouvre pas ?' : 'Besoin d’aide ?'} <ArrowRight size={16} aria-hidden="true" /></button>
          </div>}

          <details className="update-help">
            <summary><ShieldCheck size={17} aria-hidden="true" /><span>Avant de mettre à jour</span><ChevronDown size={16} aria-hidden="true" /></summary>
            <p>{platform === 'ios' ? 'Gardez la copie actuelle de Nanashi et le même compte SideStore. Ne désinstallez pas l’app. Exportez une sauvegarde récente de votre historique avant la mise à jour.' : 'Gardez votre copie Nanashi installée et exportez une sauvegarde récente. Si vous venez de NOOP ou d’un autre téléphone, importez cette sauvegarde dans Nanashi : le transfert n’est pas automatique.'}</p>
          </details>
          <details className="install-help" open={helpOpen} onToggle={event => setHelpOpen(event.currentTarget.open)}>
            <summary>Autres options et aide <ChevronDown size={16} aria-hidden="true" /></summary>
            {platform === 'ios' && <>
              <h4>SideStore ne s’ouvre pas</h4><p>Si SideStore n’est pas encore configurée, choisissez « Première installation ». Si elle est déjà prête, ouvrez cette page dans Safari et réessayez. Le lien doit être ouvert sur l’iPhone.</p>
              {source && <><h4>Retrouver les prochaines versions</h4><p>Vous pouvez aussi ajouter la source Nanashi à SideStore. Dans SideStore → Sources → +, collez cette adresse :</p><CopyValue value={source.sourceURL} label="Copier l’adresse de la source SideStore" />
                {phone === 'ios' && <GlassLink href={source.addSourceURL}>Ajouter la source à SideStore <ArrowUpRight size={16} aria-hidden="true" /></GlassLink>}</>}
              <h4>Renouvellement automatique</h4><p>Avec un compte Apple gratuit, la signature dure 7 jours. Le renouvellement SideStore dépend du Wi-Fi, du VPN local et des services Apple. Votre raccourci habituel reste inchangé ; renouveler la signature n’installe pas automatiquement une nouvelle version de Nanashi.</p>
            </>}
            {platform === 'android' && <><h4>Android bloque l’installation ?</h4><p>Autorisez l’installation depuis votre navigateur dans les réglages du téléphone, puis rouvrez le fichier téléchargé. Un appareil géré par une entreprise peut interdire cette installation.</p></>}
            {artifact && <><h4>Fichier et vérification</h4><a className="text-link" href={artifact.downloadURL}>Télécharger le fichier {platform === 'ios' ? 'IPA' : 'APK'} <ArrowDownToLine size={16} aria-hidden="true" /></a><ArtifactDetails artifact={artifact} /></>}
            <a className="text-link" href={`${REPOSITORY}/releases`} target="_blank" rel="noreferrer">Voir toutes les publications <ArrowUpRight size={16} aria-hidden="true" /></a>
          </details>
        </div>
      </div>
      {!phone && <aside className="phone-handoff" id="ouvrir-sur-telephone" aria-labelledby="handoff-heading">
        <span className="handoff-icon"><Smartphone size={23} aria-hidden="true" /></span>
        <h3 id="handoff-heading">Continuez sur votre téléphone.</h3>
        <p>Ouvrez l’appareil photo de votre téléphone et scannez ce code.</p>
        <img className="install-qr" src="/install-qr.svg" width="156" height="156" alt="Ouvrir cette page sur votre téléphone" />
        <div className="handoff-copy"><CopyValue value="https://nanashi-mk.vercel.app/#installer" label="Copier le lien pour mon téléphone" /></div>
        <p className="handoff-footnote">Le même lien vous proposera la version adaptée à votre téléphone.</p>
      </aside>}
    </GlassPanel>
    {release && <a className="release-notes" href={release.releaseURL}>Les nouveautés de la version {release.version} <ArrowUpRight size={16} aria-hidden="true" /></a>}
  </section>
}
