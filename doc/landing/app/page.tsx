import Image from "next/image";

const orbitNodes = ["Notes", "Reminders", "Calendar", "AI Client"];

const testimonials = [
  {
    quote: "Finally, an MCP server that respects the way Mac users actually work.",
    author: "Independent macOS developer",
  },
  {
    quote:
      "Orbit made my assistant useful without making my private notes someone else's database.",
    author: "AI tooling founder",
  },
  {
    quote: "The missing local context layer for developers building with MCP clients.",
    author: "Product engineer",
  },
];

const features = [
  {
    title: "Local context, not cloud sync",
    body:
      "Your AI reads from your Mac through Orbit. Your personal data does not become another vendor's training set.",
  },
  {
    title: "Notes become usable memory",
    body:
      "Ask your AI about ideas, drafts, references, and saved thoughts already living in Apple Notes.",
  },
  {
    title: "Tasks stay actionable",
    body:
      "Surface reminders, deadlines, and follow-ups without manually copying them into chat.",
  },
  {
    title: "Calendar-aware assistance",
    body:
      "Let your assistant understand your schedule before it helps you plan your day.",
  },
  {
    title: "MCP-native by design",
    body: "Built for modern AI clients that speak the Model Context Protocol.",
  },
  {
    title: "Small, quiet, Mac-native",
    body:
      "A utility that sits in your workflow instead of trying to become your workflow.",
  },
];

const steps = [
  {
    label: "01",
    title: "Install Orbit",
    body: "A lightweight macOS utility runs locally.",
  },
  {
    label: "02",
    title: "Grant Apple permissions",
    body: "Connect Notes, Reminders, and Calendar using system-level access.",
  },
  {
    label: "03",
    title: "Point your AI client to Orbit",
    body: "Your assistant can now reason with your real context.",
  },
];

const comparison = [
  ["Runs locally", "Yes", "Rarely"],
  ["Apple Notes support", "Yes", "Limited"],
  ["MCP-native", "Yes", "Not always"],
  ["Requires cloud account", "No", "Usually"],
  ["Built for developers", "Yes", "Mixed"],
  ["Data leaves your Mac", "No by design", "Often"],
];

const included = [
  "Apple Notes connection",
  "Reminders connection",
  "Calendar connection",
  "Local MCP server",
  "macOS utility app",
  "No account required",
];

const faqs = [
  {
    question: "Does Orbit upload my Apple data?",
    answer: "No. Orbit is designed as a local-first MCP server for your Mac.",
  },
  {
    question: "Which AI clients work with Orbit?",
    answer: "Any MCP-compatible client.",
  },
  {
    question: "Do I need to replace Apple Notes or Calendar?",
    answer: "No. Orbit makes your existing apps available to your AI tools.",
  },
  {
    question: "Why would developers use this?",
    answer:
      "Because AI becomes dramatically more useful when it understands your real notes, tasks, and schedule.",
  },
  {
    question: "Is it really free?",
    answer: "Yes. Orbit MCP is free to use.",
  },
];

function CheckIcon() {
  return (
    <svg viewBox="0 0 24 24" aria-hidden="true">
      <path d="m5 12 4.4 4.4L19 6.8" />
    </svg>
  );
}

export default function Home() {
  return (
    <main>
      <header className="site-header">
        <a className="brand" href="#top" aria-label="Orbit MCP home">
          <Image
            className="brand-mark"
            src="/orbit-mcp-icon.png"
            alt=""
            width={64}
            height={64}
            aria-hidden="true"
            priority
          />
          Orbit MCP
        </a>
        <nav className="nav-links" aria-label="Main navigation">
          <a href="#features">Features</a>
          <a href="#how">How it works</a>
          <a href="#compare">Compare</a>
          <a href="#pricing">Pricing</a>
          <a href="#faq">FAQ</a>
        </nav>
        <a className="nav-cta" href="#download">
          Download
        </a>
      </header>

      <section className="hero section-shell" id="top">
        <div className="hero-copy">
          <p className="eyebrow">LOCAL MCP FOR macOS</p>
          <h1>Put your Apple apps in orbit around your AI.</h1>
          <p className="hero-subtitle">
            Orbit MCP connects Notes, Reminders, and Calendar to your AI tools
            through a private local server — so your assistant finally understands
            your world without your data leaving your Mac.
          </p>
          <div className="hero-actions" id="download">
            <a className="button primary" href="#">
              Download for macOS
            </a>
            <a className="button secondary" href="#how">
              Explore the orbit
            </a>
          </div>
          <p className="microcopy">Free. Local-first. No cloud account required.</p>
        </div>

        <div className="orbit-stage" aria-label="Orbit MCP local control hub preview">
          <div className="orbit-ring ring-one" />
          <div className="orbit-ring ring-two" />
          <div className="orbit-ring ring-three" />
          {orbitNodes.map((node, index) => (
            <div className={`orbit-node node-${index + 1}`} key={node}>
              <span />
              {node}
            </div>
          ))}
          <div className="control-hub">
            <div className="window-bar">
              <span />
              <span />
              <span />
              <p>Orbit MCP</p>
            </div>
            <div className="hub-body">
              <aside>
                <Image
                  className="hub-icon"
                  src="/orbit-mcp-icon.png"
                  alt=""
                  width={176}
                  height={176}
                  aria-hidden="true"
                  priority
                />
                <nav aria-label="Connected Apple apps">
                  <span className="active">Notes</span>
                  <span>Reminders</span>
                  <span>Calendar</span>
                </nav>
              </aside>
              <section>
                <p className="mono-label">LOCAL MCP SERVER</p>
                <h2>Local MCP Server Active</h2>
                <div className="status-grid">
                  <span>Notes connected</span>
                  <span>Reminders connected</span>
                  <span>Calendar connected</span>
                  <span>No outbound sync detected</span>
                </div>
                <code>orbit-mcp --serve localhost:3941</code>
              </section>
            </div>
          </div>
        </div>
      </section>

      <section className="section-shell trust-row">
        <p>Built for developers who want AI context without cloud compromise.</p>
        <div className="testimonial-grid">
          {testimonials.map((testimonial) => (
            <article className="testimonial" key={testimonial.author}>
              <div className="stars" aria-hidden="true">
                ★★★★★
              </div>
              <blockquote>{testimonial.quote}</blockquote>
              <cite>— {testimonial.author}</cite>
            </article>
          ))}
        </div>
      </section>

      <section className="section-shell section-block" id="features">
        <div className="section-heading">
          <p className="eyebrow">LOCAL CONTEXT LAYER</p>
          <h2>Your personal system context, available where AI can use it.</h2>
        </div>
        <div className="feature-grid">
          {features.map((feature) => (
            <article className="quiet-card" key={feature.title}>
              <h3>{feature.title}</h3>
              <p>{feature.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section-shell section-block" id="how">
        <div className="section-heading">
          <p className="eyebrow">ORBITAL PATH</p>
          <h2>Three steps from local install to useful context.</h2>
        </div>
        <div className="orbital-steps">
          {steps.map((step) => (
            <article className="orbit-step" key={step.label}>
              <span>{step.label}</span>
              <h3>{step.title}</h3>
              <p>{step.body}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section-shell showcase">
        <div className="showcase-copy">
          <p className="eyebrow">COMMAND CENTER</p>
          <h2>One quiet hub for your Apple productivity context.</h2>
        </div>
        <div className="showcase-panel">
          <div className="window-bar">
            <span />
            <span />
            <span />
            <p>localhost:3941/mcp</p>
          </div>
          <div className="showcase-grid">
            <div className="showcase-main">
              <p className="mono-label">SERVER</p>
              <h3>Local server active</h3>
              <code>mcp://orbit.local/apple-context</code>
            </div>
            {["Notes", "Reminders", "Calendar", "MCP Client"].map((item) => (
              <div className="showcase-tile" key={item}>
                <CheckIcon />
                <span>{item}</span>
                <small>Connected</small>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="section-shell comparison" id="compare">
        <div className="section-heading">
          <p className="eyebrow">WHY ORBIT</p>
          <h2>Unlike cloud assistants, Orbit does not ask you to move your life somewhere else.</h2>
        </div>
        <div className="comparison-table">
          <div className="table-row table-head">
            <span />
            <strong>Orbit MCP</strong>
            <strong>Cloud sync tools</strong>
          </div>
          {comparison.map(([label, orbit, cloud]) => (
            <div className="table-row" key={label}>
              <span>{label}</span>
              <strong>{orbit}</strong>
              <em>{cloud}</em>
            </div>
          ))}
        </div>
      </section>

      <section className="section-shell pricing" id="pricing">
        <div className="section-heading">
          <p className="eyebrow">PRICING</p>
          <h2>Free because the bridge should not be the business model.</h2>
        </div>
        <article className="pricing-card">
          <div>
            <p>Orbit MCP</p>
            <strong>$0</strong>
            <span>Private local MCP server for macOS.</span>
          </div>
          <ul>
            {included.map((item) => (
              <li key={item}>
                <CheckIcon />
                {item}
              </li>
            ))}
          </ul>
          <a className="button primary" href="#download">
            Download for macOS
          </a>
          <small>No trial. No credit card. No lock-in.</small>
        </article>
      </section>

      <section className="section-shell section-block faq" id="faq">
        <div className="section-heading">
          <p className="eyebrow">FAQ</p>
          <h2>Local-first answers for a local-first tool.</h2>
        </div>
        <div className="faq-list">
          {faqs.map((faq, index) => (
            <details className="faq-item" key={faq.question} open={index === 0}>
              <summary>{faq.question}</summary>
              <p>{faq.answer}</p>
            </details>
          ))}
        </div>
        <div className="final-cta">
          <a className="button primary" href="#download">
            Download for macOS
          </a>
          <p>Free. Local-first. No cloud account required.</p>
        </div>
      </section>

      <div className="mobile-sticky-cta">
        <a className="button primary" href="#download">
          Download for macOS
        </a>
      </div>
    </main>
  );
}
