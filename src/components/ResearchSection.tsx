import { Badge } from "@/components/ui/badge";
import { Sparkles, GitBranch, FileText, Users } from "lucide-react";

const steps = [
  {
    icon: FileText,
    title: "Bring in your research",
    description: "Pipe in outputs from Claude, NotebookLM, and research tools into a shared canvas.",
  },
  {
    icon: Sparkles,
    title: "AI synthesizes findings",
    description: "Miro AI clusters insights, surfaces themes, and drafts summaries automatically.",
  },
  {
    icon: Users,
    title: "Team reviews together",
    description: "Everyone reacts, votes, and comments in real time on a shared infinite canvas.",
  },
  {
    icon: GitBranch,
    title: "Set direction",
    description: "Turn synthesized research into roadmap items, diagrams, or action plans instantly.",
  },
];

export default function ResearchSection() {
  return (
    <section className="py-20 md:py-28 bg-white">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 gap-16 lg:grid-cols-2 lg:items-center">
          {/* Left: text */}
          <div>
            <Badge className="mb-5 bg-[#F5F5F7] text-[#050038] border-0 font-semibold text-xs uppercase tracking-wide hover:bg-[#F5F5F7]">
              Research Synthesis
            </Badge>
            <h2 className="text-3xl font-extrabold text-[#050038] sm:text-4xl md:text-5xl leading-tight">
              Turn research into a shared direction.
            </h2>
            <p className="mt-5 text-lg text-[#6B6B8D] leading-relaxed">
              Miro connects your team's thinking tools into one canvas — so insights don't live in
              isolation. AI handles the synthesis so your team can focus on decisions.
            </p>
            <ul className="mt-10 space-y-6">
              {steps.map(({ icon: Icon, title, description }) => (
                <li key={title} className="flex gap-4">
                  <div className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-[#FFF3C4]">
                    <Icon className="h-5 w-5 text-[#050038]" />
                  </div>
                  <div>
                    <p className="font-semibold text-[#050038]">{title}</p>
                    <p className="mt-0.5 text-sm text-[#6B6B8D] leading-relaxed">{description}</p>
                  </div>
                </li>
              ))}
            </ul>
          </div>

          {/* Right: canvas mockup */}
          <div className="relative rounded-2xl border border-[#E5E5E5] bg-[#F5F5F7] p-6 min-h-[420px] shadow-xl overflow-hidden">
            {/* Cluster header */}
            <div className="mb-4 flex items-center gap-2">
              <div className="h-3 w-3 rounded-full bg-[#FFD02F]" />
              <span className="text-xs font-semibold text-[#050038] uppercase tracking-wider">
                AI Theme Clusters
              </span>
            </div>
            {/* Theme cards */}
            <div className="grid grid-cols-2 gap-3">
              {[
                { color: "#FFD02F", title: "User Frustrations", count: "12 notes" },
                { color: "#A8EDEA", title: "Desired Features", count: "8 notes" },
                { color: "#FECDD3", title: "Workflow Gaps", count: "15 notes" },
                { color: "#D0F0C0", title: "Quick Wins", count: "6 notes" },
              ].map(({ color, title, count }) => (
                <div
                  key={title}
                  className="rounded-xl p-4 text-sm font-medium text-[#050038]"
                  style={{ backgroundColor: color + "40", borderLeft: `3px solid ${color}` }}
                >
                  <p className="font-semibold">{title}</p>
                  <p className="mt-1 text-xs text-[#6B6B8D]">{count}</p>
                </div>
              ))}
            </div>
            {/* AI summary card */}
            <div className="mt-4 rounded-xl border border-[#E5E5E5] bg-white p-4 shadow-sm">
              <div className="flex items-center gap-2 mb-2">
                <Sparkles className="h-4 w-4 text-[#FFD02F]" />
                <span className="text-xs font-semibold text-[#050038]">AI Summary</span>
              </div>
              <p className="text-xs text-[#6B6B8D] leading-relaxed">
                Users primarily struggle with <strong className="text-[#050038]">workflow handoffs</strong> between
                tools. Most requested feature is a unified dashboard with AI-assisted prioritization.
              </p>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
