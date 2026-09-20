import { LatticesLogo } from './LandingPage'
import { ProductsMenu } from './SiteChrome'
const downloadUrl = 'https://github.com/arach/lattices/releases/download/speech-v0.2.0/Speech.dmg'
const sourceUrl = 'https://github.com/arach/lattices/tree/main/products/speech'
export default function SpeechPage() {
  return <div className="action-page speech-page">
    <nav className="nav action-nav" aria-label="Speech navigation"><div className="nav-inner">
      <a href="/" className="nav-brand action-family-lockup"><LatticesLogo size={20} /><span className="nav-name">lattices</span><span aria-hidden="true">/</span><span>speech</span></a>
      <div className="nav-links"><ProductsMenu /><a className="nav-link" href={sourceUrl}>Source</a><a className="action-nav-download" href={downloadUrl}>Download</a></div>
    </div></nav>
    <main className="action-shell">
      <section className="action-hero" aria-labelledby="speech-title"><div className="action-hero-copy">
        <h1 id="speech-title">Keep listening.</h1>
        <p className="action-hero-lead">Speech is a standalone player from Lattices. Queue text, choose a voice, and control playback from its own menu bar app.</p>
        <div className="action-hero-actions"><a className="hero-primary-cta action-primary-cta" href={downloadUrl}>Download Speech</a><a className="hero-secondary-cta" href={sourceUrl}>Read the source</a></div>
        <p className="action-platform-note">macOS 26+ · Apple silicon</p>
      </div></section>
      <section className="action-proof" aria-labelledby="speech-controls"><div className="action-section-heading"><h2 id="speech-controls">A player that owns its playback.</h2></div>
        <div className="action-proof-lines">
          <article><h3>Independent of the workspace</h3><p>Install from the Apps menu in Lattices or download directly. Speech owns its queue and keeps running when a client disconnects.</p></article>
          <article><h3>Your choice of voice</h3><p>Use system voices or configure a supported cloud or local provider. Speech keeps provider settings and playback controls together.</p></article>
          <article><h3>One place to return</h3><p>Automatic mode hides the companion icon while Lattices is running. Choose Always show in Speech settings, or reopen Speech to reach its controls.</p></article>
        </div>
      </section>
    </main>
    <footer className="action-footer"><div className="action-footer-inner"><span>Speech is a Lattices product.</span><div><a href="/">Lattices</a><a href="/blink">Blink</a><a href="/action">Action</a><a href={sourceUrl}>Source</a></div></div></footer>
  </div>
}
