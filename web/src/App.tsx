import { useEffect } from 'react'
import { ArrowDown, ArrowDownToLine, ArrowRight, ArrowUpRight, Bluetooth, ChevronDown, CodeXml, HeartPulse, LockKeyhole, MoonStar, Sparkles, Waves } from 'lucide-react'
import { Eyebrow, GlassLink, GlassPanel } from './components/Glass'
import { InstallSection } from './components/InstallSection'
import { REPOSITORY } from './lib/releases'

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
  return <>
    <a href="#main" className="skip-link">Aller au contenu</a>
    <div className="ambient" aria-hidden="true" />
    <header className="site-header page-width" id="accueil">
      <a href="#accueil" className="brand" aria-label="Nanashi, accueil"><img src="/icon-192.png" width="42" height="42" alt="" /><span>nanashi<span className="brand-dot">.</span></span></a>
      <nav aria-label="Navigation principale"><a href="#experience">L’expérience</a><a href="#questions">Questions</a><a className="header-download" href="#installer">Installer <ArrowDown size={15} aria-hidden="true" /></a></nav>
    </header>
    <main id="main">
      <section className="hero page-width" aria-labelledby="hero-heading">
        <div className="hero-copy"><Eyebrow><span className="small-line" /> L’essentiel, à votre rythme</Eyebrow>
          <h1 id="hero-heading">Votre rythme.<br /><span>Vos règles.</span></h1>
          <p className="hero-description">Vos nuits, votre récupération, votre activité.<br className="desktop-break" /> Enfin réunies dans une app qui vous ressemble.</p>
          <div className="hero-actions"><GlassLink className="primary" href="#installer">Installer Nanashi <ArrowDownToLine size={18} /></GlassLink><a className="quiet-link" href="#experience">Découvrir l’app <ArrowRight size={17} /></a></div>
          <div className="hero-assurances"><span><Bluetooth size={15} /> Connexion directe au bracelet</span><span><LockKeyhole size={15} /> Historique sur votre appareil</span></div>
          <div className="hero-footnote"><span>01 /</span><p>Moins de bruit.<br />Plus de place pour vous.</p></div>
        </div>
        <figure className="hero-visual">
          <div className="orbit orbit-one" aria-hidden="true" /><div className="orbit orbit-two" aria-hidden="true" />
          <div className="phone"><div className="phone-speaker" aria-hidden="true" /><img src="/app-preview.jpg" alt="Aperçu de Nanashi : tableau de bord Aujourd’hui avec les scores de charge, d’effort et de repos, la dernière nuit et les cinq onglets de navigation." width="476" height="1030" fetchPriority="high" /></div>
          <GlassPanel className="floating-label"><span className="label-icon"><MoonStar size={22} aria-hidden="true" /></span><div><span className="small-label">Chaque nuit compte</span><strong>Comprendre. Récupérer.</strong></div></GlassPanel>
          <figcaption>Aperçu iPhone · données de démonstration</figcaption>
        </figure>
      </section>
      <div className="principles page-width"><span><Waves size={18} aria-hidden="true" /> Sommeil</span><span><HeartPulse size={18} aria-hidden="true" /> Récupération</span><span><ArrowUpRight size={18} aria-hidden="true" /> Activité</span><span><Sparkles size={18} aria-hidden="true" /> Coach personnel</span></div>
      <section id="experience" className="experience-section page-width section" aria-labelledby="experience-heading">
        <div className="section-heading"><div><Eyebrow>Le quotidien, plus lisible</Eyebrow><h2 id="experience-heading">Des données.<br /><span>Et ce qu’elles vous disent.</span></h2></div><p>Une interface claire pour revenir à ce qui compte.<br />Du premier regard au détail d’une nuit.</p></div>
        <div className="feature-grid">
          <article className="feature"><span className="feature-number">01 — COMPRENDRE</span><MoonStar className="feature-icon" size={29} aria-hidden="true" /><h3>La nuit a son histoire.</h3><p>Retrouvez vos nuits, leurs horaires et leur chronologie. Comparez deux nuits sans perdre le fil de votre historique.</p><div className="feature-baseline"><span>Sommeil & historique</span><ArrowUpRight size={17} aria-hidden="true" /></div></article>
          <article className="feature"><span className="feature-number">02 — AJUSTER</span><HeartPulse className="feature-icon" size={29} aria-hidden="true" /><h3>De la mesure au rythme.</h3><p>Récupération, effort et repos se lisent ensemble. Vos séances et vos tendances trouvent leur place dans une même vue.</p><div className="feature-baseline"><span>Jour & activité</span><ArrowUpRight size={17} aria-hidden="true" /></div></article>
          <article className="feature"><span className="feature-number">03 — ÉCHANGER</span><Sparkles className="feature-icon" size={29} aria-hidden="true" /><h3>Un Coach qui a du contexte.</h3><p>Posez vos questions à partir de vos mesures. L’IA reste optionnelle, avec votre fournisseur, votre clé et votre accord de partage.</p><div className="feature-baseline"><span>Coach & remarques</span><ArrowUpRight size={17} aria-hidden="true" /></div></article>
        </div>
        <div className="privacy-line"><LockKeyhole size={19} aria-hidden="true" /><p>Le suivi fonctionne sur l’appareil. Ce site ne reçoit pas vos données de sommeil ou de santé.</p><a href="#confidentialite">En savoir plus <ArrowRight size={15} /></a></div>
      </section>
      <div className="page-width"><InstallSection /></div>
      <section className="faq-section page-width section" id="questions" aria-labelledby="faq-heading">
        <div><Eyebrow>Sans zone grise</Eyebrow><h2 id="faq-heading">Avant de<br /><span>vous lancer.</span></h2><a className="quiet-link" href={`${REPOSITORY}/issues`} target="_blank" rel="noreferrer">Signaler un problème <ArrowUpRight size={16} /></a></div>
        <div className="faq-list">
          <details><summary>Quels bracelets puis-je connecter ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Nanashi est basée sur NOOP et communique directement en Bluetooth avec les bracelets WHOOP 4.0 et 5.0/MG. Les fonctions Oura présentes dans le code sont expérimentales. La disponibilité d’une mesure dépend du bracelet, de son appairage et des données enregistrées.</p></details>
          <details><summary>Est-ce une app officielle WHOOP ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Non. Nanashi est une adaptation indépendante de NOOP, développée à partir de son code source. Elle n’est ni affiliée ni approuvée par WHOOP. Les estimations locales peuvent différer des résultats de l’application officielle et ne constituent pas un diagnostic médical.</p></details>
          <details><summary>Faut-il un abonnement ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Nanashi n’ajoute pas d’abonnement pour le suivi local. Un fournisseur d’IA peut facturer l’utilisation de votre clé API. L’installation iPhone reste soumise aux règles de signature Apple : un compte gratuit implique un renouvellement périodique.</p></details>
          <details><summary>Mes données suivent-elles une mise à jour ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Une mise à jour compatible s’installe sur la copie existante. Ne désinstallez pas Nanashi et conservez une sauvegarde récente. Une nouvelle installation sur un autre téléphone ne transfère pas automatiquement l’historique : utilisez l’export et l’import de sauvegarde de l’app.</p></details>
          <details id="confidentialite"><summary>Qu’est-ce qui est envoyé en ligne ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Ce site lit un catalogue public de versions pour afficher les téléchargements. Il n’utilise ni analyse d’audience, ni cookie publicitaire, ni formulaire de données de santé. L’hébergeur traite les données techniques nécessaires à la connexion, comme l’adresse IP.</p><p>Dans l’app, les mesures et l’historique restent sur l’appareil. Si vous activez le Coach ou les remarques IA, le contexte autorisé est envoyé au fournisseur choisi. Les services externes que vous configurez conservent leurs propres conditions.</p></details>
          <details><summary>D’où viennent le code et le design ? <ChevronDown size={18} aria-hidden="true" /></summary><p>Le socle de l’app vient de <a href="https://github.com/ryanbr/noop" target="_blank" rel="noreferrer">NOOP par @ryanbr et ses contributeurs</a>, sous licence PolyForm Noncommercial 1.0.0. Nanashi conserve leurs crédits et les conditions de cette licence.</p><p>Les surfaces et commandes du site adaptent <a href="https://21st.dev/@educalvolpz/components/glass-card" target="_blank" rel="noreferrer">Glass Card par @educalvolpz</a>, <a href="https://21st.dev/@jahed/components/glass-button" target="_blank" rel="noreferrer">Glass Button par @jahed</a> et <a href="https://21st.dev/@ruixen.ui/components/pill-morph-tabs" target="_blank" rel="noreferrer">Pill Morph Tabs par @ruixen.ui</a> de 21st.dev. La palette reprend Harbor Blue. Les images montrent l’application Nanashi, avec des données synthétiques.</p></details>
        </div>
      </section>
    </main>
    <footer className="site-footer page-width"><div className="footer-top"><a href="#accueil" className="brand"><img src="/icon-192.png" width="38" height="38" alt="" /><span>nanashi<span className="brand-dot">.</span></span></a><p>Votre rythme. Vos règles.</p><a href={REPOSITORY} target="_blank" rel="noreferrer" className="github-link"><CodeXml size={17} aria-hidden="true" /> Le code sur GitHub <ArrowUpRight size={15} /></a></div><div className="footer-bottom"><span>Adaptation indépendante de NOOP · Usage non commercial</span><div><a href="#confidentialite">Confidentialité</a><a href={`${REPOSITORY}/blob/main/LICENSE`} target="_blank" rel="noreferrer">Licence</a><a href="https://21st.dev" target="_blank" rel="noreferrer">Design avec 21st.dev</a></div></div></footer>
  </>
}

export default App
