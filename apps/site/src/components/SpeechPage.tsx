import { SiteHeader } from './SiteChrome'

const downloadUrl = 'https://github.com/arach/lattices/releases/download/speech-v0.2.0/Speech.dmg'
const sourceUrl = 'https://github.com/arach/lattices/tree/main/products/speech'

const features = [
  {
    title: 'A unified speak API',
    description:
      'Any agent can say things out loud through one local interface — queue text, pick a voice, and playback keeps running even if the client disconnects.',
  },
  {
    title: 'Background by default',
    description:
      'A task finishes and its summary is queued and spoken while you keep working. Define it once and every agent you run gets a voice.',
  },
  {
    title: 'A readalong when you want it',
    description:
      'Speech shows a lightweight HUD over the workspace while it reads — follow along, or let it run quietly and check the queue later.',
  },
]

export default function SpeechPage() {
  return (
    <div className="family-page speech-page">
      <SiteHeader />
      <main>
        <section className="family-hero" aria-labelledby="speech-title">
          <div className="family-hero-copy">
            <p className="family-kicker">Speech — a voice for agents</p>
            <h1 id="speech-title">Give your agents a voice.</h1>
            <p>
              Speech is a standalone player from Lattices: one API for agents and
              scripts to queue spoken readouts, with an optional HUD readalong.
              Powered by Lattices, it can go ambient — a download finished, a
              build done — spoken in the background.
            </p>
            <div className="family-hero-actions">
              <a href={downloadUrl}>Download Speech</a>
              <a href={sourceUrl}>Read the source</a>
            </div>
            <p className="speech-platform-note">macOS 26+ · Apple silicon</p>
          </div>
          <div className="family-speech-visual speech-queue-hero" aria-hidden="true">
            <div className="is-playing">
              <span>▶</span>
              <strong>Agent summary — release build</strong>
              <time>02:14</time>
            </div>
            <div>
              <span>02</span>
              <strong>Download finished</strong>
              <time>00:08</time>
            </div>
            <div>
              <span>03</span>
              <strong>Release notes draft</strong>
              <time>01:42</time>
            </div>
          </div>
        </section>

        <section className="speech-features" aria-label="What Speech does">
          {features.map((feature) => (
            <article key={feature.title}>
              <h2>{feature.title}</h2>
              <p>{feature.description}</p>
            </article>
          ))}
        </section>

        <section className="family-close">
          <div>
            <p className="family-kicker">Independent, always listening</p>
            <h2>Speech owns its queue and keeps running when a client disconnects.</h2>
          </div>
          <nav aria-label="Lattices products">
            <a href="/">Lattices</a>
            <a href="/action">Action</a>
            <a href="/blink">Blink</a>
            <a href="/family">Family</a>
          </nav>
        </section>
      </main>
      <footer className="family-footer">
        <span>Speech is a Lattices product.</span>
        <nav aria-label="Footer">
          <a href="/docs/overview">Docs</a>
          <a href="/blog">Blog</a>
          <a href="https://github.com/arach/lattices">GitHub</a>
        </nav>
      </footer>
    </div>
  )
}
