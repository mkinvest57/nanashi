import { useEffect } from 'react'
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUpRight, Bluetooth, Check, ChevronDown, CodeXml, Database, HeartPulse, LockKeyhole, MoonStar, Sparkles } from 'lucide-react'
import { GlassLink, GlassPanel } from './components/Glass'
import { InstallSection } from './components/InstallSection'
import { ProductExperience } from './components/ProductExperience'
import { REPOSITORY } from './lib/releases'
import './marketing.css'

const capabilities = [
  { title: 'Sommeil', description: 'Retrouvez chaque nuit.', icon: MoonStar },
  { title: 'Récupération', description: 'Lisez vos tendances.', icon: HeartPulse },
  { title: 'Activité', description: 'Donnez du contexte à l’effort.', icon: ArrowUpRight },
  { title: 'Coach', description: 'Posez vos questions.', icon: Sparkles },
]

function App() {
  useEffect(() => {
    const revealLinkedDetail = () => {
      if (window.location.hash === '#confidentialite') {
        const detail = document.getElementById('confidentialite')
        if (detail instanceof HTMLDetailsElement) detail.open = true
      }
    }
    revealLinkedDetail()
    window.addEventListener('hashchange', revealLinkedDetail)
    return () => window.removeEventListener('hashchange', revealLinkedDetail)
  }, [])

  return <div className="mkt-page">
    <a href="#main" className="skip-link">Aller au contenu</a>
    <div className="mkt-announcement"><span>VOTRE BRACELET. VOTRE LIBERTÉ.</span><a href="#compatibilite">Voir les compatibilités <ArrowUpRight size={13} aria-hidden="true" /></a></div>
    <header className="mkt-header mkt-width" id="accueil">
      <a href="#accueil" className="brand" aria-label="Nanashi, accueil"><img src="/icon-192.png" width="38" height="38" alt="" /><span>nanashi<span className="brand-dot">.</span></span></a>
      <nav aria-label="Navigation principale"><a href="#experience">L’expérience</a><a href="#compatibilite">Compatibilité</a><a href="#questions">Questions</a></nav>
      <GlassLink href="#installer" className="mkt-header-cta">Installer Nanashi <ArrowUpRight size={15} aria-hidden="true" /></GlassLink>
    </header>
    <main id="main">
      {/* Layered product composition adapted from @vaib215/hero-with-product-mockup,
          with the static orbital stage from @daiwiikharihar/spatial-product-showcase. */}
      <section className="mkt-hero mkt-width" aria-labelledby="hero-heading">
        <div className="mkt-hero-copy"><p className="mkt-kicker"><span />LE SUIVI QUI VOUS APPARTIENT</p>
          <h1 id="hero-heading">Votre WHOOP.<br /><span>Sans abonnement WHOOP.</span></h1>
          <p className="mkt-hero-description">Gardez votre bracelet. Retrouvez votre sommeil, votre récupération et votre activité dans <strong>Nanashi.</strong></p>
          <div className="mkt-hero-actions"><GlassLink className="primary" href="#installer">Installer Nanashi <ArrowDownToLine size={18} aria-hidden="true" /></GlassLink><a className="mkt-text-link" href="#experience">Explorer l’app <ArrowDown size={17} aria-hidden="true" /></a></div>
          <p className="mkt-hero-compat"><Bluetooth size={15} aria-hidden="true" /> WHOOP 4.0 et 5.0 / MG<span>·</span> iPhone & Android</p>
          <div className="mkt-hero-note"><LockKeyhole size={17} aria-hidden="true" /><p>Vos mesures. Sur votre appareil.<br /><span>Une app indépendante, pensée pour votre quotidien.</span></p></div>
        </div>
        <figure className="mkt-hero-scene">
          <div className="mkt-orbit mkt-orbit-one" aria-hidden="true" /><div className="mkt-orbit mkt-orbit-two" aria-hidden="true" />
          <div className="mkt-scene-word" aria-hidden="true">NANASHI</div>
          <div className="mkt-phone-back mkt-device" aria-hidden="true"><img src="/app-sleep.jpg" alt="" width="600" height="1299" /></div>
          <div className="mkt-phone-main mkt-device"><img src="/app-preview.jpg" alt="Nanashi sur iPhone : scores de récupération, effort et repos, avec des données de démonstration" width="476" height="1030" fetchPriority="high" /></div>
          <GlassPanel className="mkt-signal-tag"><Bluetooth size={17} aria-hidden="true" /><div><strong>Du bracelet à vous.</strong><span>Connexion Bluetooth directe</span></div></GlassPanel>
          <div className="mkt-scene-label"><span>01—05</span> UN NOUVEAU REGARD SUR VOS DONNÉES</div>
          <figcaption>Aperçus iPhone de Nanashi · données de démonstration</figcaption>
        </figure>
      </section>
      <div className="mkt-capabilities mkt-width">{capabilities.map(item => <div key={item.title}><item.icon size={23} aria-hidden="true" /><p><strong>{item.title}</strong><span>{item.description}</span></p></div>)}</div>
      <section className="mkt-manifesto mkt-section mkt-width" aria-labelledby="manifesto-heading">
        <div><p className="mkt-kicker">LE MATÉRIEL RESTE. L’EXPÉRIENCE CHANGE.</p><h2 id="manifesto-heading">Votre corps ne devrait<br />pas être <span>un abonnement.</span></h2></div>
        <div className="mkt-manifesto-body"><p>Votre WHOOP capte les signaux. Nanashi vous aide à les lire, directement sur votre téléphone, sans abonnement WHOOP requis pour son suivi local.</p><div className="mkt-manifesto-points"><span><Check size={17} aria-hidden="true" />Gardez votre bracelet compatible</span><span><Check size={17} aria-hidden="true" />Retrouvez vos nuits et vos séances</span><span><Check size={17} aria-hidden="true" />Restez maître de votre historique</span></div><a href="#compatibilite" className="mkt-text-link">Mon bracelet est-il compatible ? <ArrowRight size={16} aria-hidden="true" /></a></div>
      </section>
      <ProductExperience />
      <section className="mkt-ownership mkt-width" aria-labelledby="ownership-heading">
        <div className="mkt-ownership-mark" aria-hidden="true"><LockKeyhole size={34} strokeWidth={1.3} /></div><div><p className="mkt-kicker">PERSONNEL. VRAIMENT.</p><h2 id="ownership-heading">Votre historique<br /><span>reste entre vos mains.</span></h2></div><div className="mkt-ownership-body"><p>Vos mesures sont stockées sur l’appareil. Consultez votre historique, exportez une sauvegarde et retrouvez ce qui compte pour vous.</p><a href="#confidentialite" className="mkt-text-link">Comprendre la confidentialité <ArrowUpRight size={16} aria-hidden="true" /></a></div>
      </section>
      <section className="mkt-compatibility mkt-section mkt-width" id="compatibilite" aria-labelledby="compatibility-heading">
        <div className="mkt-section-head"><div><p className="mkt-kicker">LE BON LIEN AVEC VOTRE BRACELET</p><h2 id="compatibility-heading">Commencez avec<br /><span>ce que vous avez.</span></h2></div><p>Connexion directe ou import d’historique :<br className="mkt-desktop" /> chaque source a sa place.</p></div>
        {/* Highlighted-column hierarchy adapted from Hirael Comparison 2 (MIT). */}
        <div className="mkt-compat-grid">
          <article className="mkt-compatible-primary"><div className="mkt-compatible-top"><span className="mkt-chip"><Bluetooth size={14} aria-hidden="true" />CONNEXION DIRECTE</span><ArrowUpRight size={22} aria-hidden="true" /></div><h3>WHOOP<span>4.0 · 5.0 · MG</span></h3><p>Connectez votre bracelet en Bluetooth. Nanashi enregistre vos mesures et calcule ses propres estimations de sommeil, de récupération et d’effort.</p><div className="mkt-compatible-bottom"><span><Check size={16} aria-hidden="true" />Sans abonnement WHOOP</span><GlassLink href="#installer" className="primary">Utiliser mon WHOOP <ArrowRight size={16} aria-hidden="true" /></GlassLink></div></article>
          <article className="mkt-compatible-secondary"><span className="mkt-chip"><Database size={14} aria-hidden="true" />IMPORT D’HISTORIQUE</span><h3>Xiaomi<span>via Mi Fitness</span></h3><p>Votre passé compte aussi. Importez les données d’un export Mi Fitness compatible pour retrouver votre historique dans Nanashi.</p><a href="#compatibility-details" className="mkt-text-link" onClick={() => { const detail = document.getElementById('compatibility-details'); if (detail instanceof HTMLDetailsElement) detail.open = true }}>Voir les formats et limites <ArrowRight size={16} aria-hidden="true" /></a></article>
        </div>
        <details className="mkt-compat-details" id="compatibility-details"><summary>Le détail des connexions et des données <ChevronDown size={18} aria-hidden="true" /></summary><div><p><strong>WHOOP 4.0, 5.0 et MG.</strong> La disponibilité de chaque mesure dépend du modèle, de l’appairage et des données enregistrées. Nanashi est indépendante de WHOOP ; ses estimations ne sont pas celles de l’app officielle.</p><p><strong>Xiaomi / Mi Fitness.</strong> Import local d’exports compatibles ; cela ne signifie pas que tous les bracelets Xiaomi se connectent directement en Bluetooth. Les exports Smart Band 8, 9 et 10 sont prévus par le parcours d’import ; les données dépendent du fichier fourni.</p><p><strong>Apple Santé et autres sources.</strong> Sur iPhone, choisissez les données autorisées dans Apple Santé. Les capteurs cardiaques Bluetooth compatibles fournissent la fréquence cardiaque en direct. Les fonctions Oura restent expérimentales.</p></div></details>
      </section>
      <section className="mkt-freedom mkt-width" aria-labelledby="freedom-heading"><div><p className="mkt-kicker">PLUS DE PLACE POUR VOUS</p><h2 id="freedom-heading">Le prochain mouvement<br /><span>vous appartient.</span></h2><p>Une séance. Une meilleure nuit. Un peu de recul.<br />À vous de choisir ce que vos données vous apportent.</p></div><a href="#installer" className="mkt-round-link" aria-label="Accéder à l’installation de Nanashi"><ArrowDownRightIcon /></a></section>
      <div className="mkt-install mkt-width"><InstallSection /></div>
      <section className="mkt-faq mkt-section mkt-width" id="questions" aria-labelledby="faq-heading"><div><p className="mkt-kicker">QUELQUES RÉPONSES, SIMPLEMENT</p><h2 id="faq-heading">Avant votre<br /><span>premier signal.</span></h2><a className="mkt-text-link" href={`${REPOSITORY}/issues`} target="_blank" rel="noreferrer">Une autre question ? <ArrowUpRight size={16} aria-hidden="true" /></a></div><div className="mkt-faq-list">
        <details><summary>Je peux vraiment utiliser mon WHOOP sans abonnement WHOOP ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Oui, le suivi local de Nanashi communique directement en Bluetooth avec un WHOOP 4.0 ou 5.0/MG compatible. Il ne nécessite pas d’abonnement WHOOP. Nanashi calcule ses propres estimations ; elle ne donne pas accès aux services ni à toutes les fonctions de l’application officielle.</p></details>
        <details><summary>Comment installer Nanashi sur mon téléphone ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Le guide propose le téléchargement Android et le parcours iPhone adapté à votre situation. Sur iPhone, l’installation initiale passe par un ordinateur et AltStore ou SideStore. La signature Apple gratuite doit être renouvelée périodiquement ; le guide explique la configuration. <a href="#installer">Ouvrir l’installation</a>.</p></details>
        <details><summary>Et si j’ai déjà Nanashi ou SideStore ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Sélectionnez votre situation dans la section Installation. Gardez la même copie de Nanashi et faites une sauvegarde avant une mise à jour. Ne supprimez pas votre installation actuelle : une copie installée sur un autre téléphone ne récupère pas automatiquement son historique.</p></details>
        <details><summary>Comment fonctionne le Coach ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Le Coach est une fonction IA optionnelle. Vous choisissez votre fournisseur, ajoutez votre clé API et autorisez le contexte partagé. Le fournisseur peut facturer l’usage. Le Coach aide à comprendre vos données ; il ne remplace pas un professionnel de santé.</p></details>
        <details id="confidentialite"><summary>Qui peut voir mes données ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Les mesures et l’historique sont stockés sur votre appareil. Si vous activez le Coach ou les remarques IA, le contexte autorisé est envoyé au fournisseur choisi. Les services externes que vous configurez conservent leurs propres conditions.</p><p>Ce site ne reçoit pas vos mesures de santé. Il lit uniquement un catalogue public de versions, sans analyse d’audience ni cookie publicitaire. L’hébergeur traite les données techniques nécessaires à la connexion, comme l’adresse IP.</p></details>
        <details><summary>D’où vient Nanashi ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Nanashi est une adaptation indépendante de <a href="https://github.com/ryanbr/noop" target="_blank" rel="noreferrer">NOOP par @ryanbr et ses contributeurs</a>, sous licence PolyForm Noncommercial 1.0.0. Elle n’est ni affiliée ni approuvée par WHOOP. Les crédits et conditions du code d’origine sont conservés.</p><p>Le design adapte des composants de 21st.dev : <a href="https://21st.dev/@vaib215/components/hero-with-product-mockup" target="_blank" rel="noreferrer">Product Mockup</a>, <a href="https://21st.dev/@daiwiikharihar/components/spatial-product-showcase" target="_blank" rel="noreferrer">Spatial Product Showcase</a>, <a href="https://21st.dev/@mohammadshehadeh/components/feature-11" target="_blank" rel="noreferrer">Feature Tab Switcher</a>, <a href="https://21st.dev/@mohammadshehadeh/components/comparison-02" target="_blank" rel="noreferrer">Comparison Table</a>, <a href="https://21st.dev/@educalvolpz/components/glass-card" target="_blank" rel="noreferrer">Glass Card</a>, <a href="https://21st.dev/@jahed/components/glass-button" target="_blank" rel="noreferrer">Glass Button</a> et <a href="https://21st.dev/@ruixen.ui/components/pill-morph-tabs" target="_blank" rel="noreferrer">Pill Morph Tabs</a>. La <a href="/licenses/hirael.txt">licence MIT des composants Hirael</a> est conservée.</p></details>
      </div></section>
    </main>
    <footer className="mkt-footer mkt-width"><div className="mkt-footer-top"><a href="#accueil" className="brand"><img src="/icon-192.png" width="38" height="38" alt="" /><span>nanashi<span className="brand-dot">.</span></span></a><p>Votre rythme. Vos règles.</p><a href={REPOSITORY} target="_blank" rel="noreferrer" className="mkt-text-link"><CodeXml size={17} aria-hidden="true" />Le code sur GitHub <ArrowUpRight size={15} aria-hidden="true" /></a></div><div className="mkt-footer-bottom"><span>Adaptation indépendante de NOOP · Usage non commercial</span><div><a href="#confidentialite">Confidentialité</a><a href={`${REPOSITORY}/blob/main/LICENSE`} target="_blank" rel="noreferrer">Licence</a><a href="https://21st.dev" target="_blank" rel="noreferrer">Design avec 21st.dev</a></div></div></footer>
  </div>
}
function ArrowDownRightIcon() { return <ArrowUpRight size={36} strokeWidth={1.4} className="mkt-down-arrow" aria-hidden="true" /> }
export default App
