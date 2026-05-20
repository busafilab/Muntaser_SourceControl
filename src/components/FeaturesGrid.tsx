import { Sparkles, Layers, LayoutTemplate, GitBranch, Shield, Plug } from "lucide-react";

const features = [
  {
    icon: Sparkles,
    color: "#FFF3C4",
    title: "AI",
    description:
      "Accelerate your team with collaborative AI workflows. Let agents handle the synthesis, clustering, and drafting.",
  },
  {
    icon: Layers,
    color: "#EDE9FE",
    title: "Intelligent Canvas",
    description:
      "An infinite multiplayer canvas that adapts to how your team thinks — flexible, fast, and always in sync.",
  },
  {
    icon: LayoutTemplate,
    color: "#DBEAFE",
    title: "Formats",
    description:
      "Docs, Tables, Slides, and Diagrams all live side-by-side. No context-switching between apps.",
  },
  {
    icon: GitBranch,
    color: "#D0F0C0",
    title: "Blueprints",
    description:
      "Automate repeatable processes with smart templates and flow triggers built right into the canvas.",
  },
  {
    icon: Shield,
    color: "#FFE4E6",
    title: "Enterprise Security",
    description:
      "ISO 42001, ISO 27001, SOC 2, and GDPR compliant. Enterprise-grade access controls and audit logs.",
  },
  {
    icon: Plug,
    color: "#E0F2FE",
    title: "Integrations",
    description:
      "250+ native integrations including Jira, Slack, GitHub, Figma, and your favourite AI tools.",
  },
];

export default function FeaturesGrid() {
  return (
    <section className="py-20 md:py-28 bg-[#F5F5F7]">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-14">
          <h2 className="text-3xl font-extrabold text-[#050038] sm:text-4xl md:text-5xl">
            Everything your team needs to innovate.
          </h2>
          <p className="mt-4 text-lg text-[#6B6B8D] max-w-2xl mx-auto">
            One workspace where ideas, plans, and execution come together — with AI as your co-pilot.
          </p>
        </div>

        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3">
          {features.map(({ icon: Icon, color, title, description }) => (
            <div
              key={title}
              className="group rounded-2xl border border-[#E5E5E5] bg-white p-6 transition-shadow hover:shadow-md"
            >
              <div
                className="mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl"
                style={{ backgroundColor: color }}
              >
                <Icon className="h-5 w-5 text-[#050038]" />
              </div>
              <h3 className="text-lg font-bold text-[#050038]">{title}</h3>
              <p className="mt-2 text-sm text-[#6B6B8D] leading-relaxed">{description}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
