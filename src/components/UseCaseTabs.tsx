"use client";

import { useState } from "react";
import { cn } from "@/lib/utils";
import { Search, Map, GitBranch, Users } from "lucide-react";

const tabs = [
  {
    id: "research",
    label: "Research",
    icon: Search,
    headline: "Synthesize research at the speed of your team.",
    description:
      "Import customer interviews, survey results, and competitive analyses. Let AI surface the themes while your team focuses on meaning.",
    color: "#FFD02F",
    bg: "#FFF3C4",
    mockupItems: ["Customer interviews", "Survey responses", "Competitive analysis", "User personas"],
  },
  {
    id: "roadmaps",
    label: "Roadmaps",
    icon: Map,
    headline: "Build roadmaps everyone actually understands.",
    description:
      "Connect strategy to execution with visual roadmaps. Link epics to outcomes and keep every stakeholder aligned.",
    color: "#7C3AED",
    bg: "#EDE9FE",
    mockupItems: ["Q1 Goals", "Feature backlog", "Launch timeline", "OKRs"],
  },
  {
    id: "diagrams",
    label: "Diagrams",
    icon: GitBranch,
    headline: "Diagram faster with AI auto-layout.",
    description:
      "From system architecture to user flows — Miro AI generates and arranges your diagrams from plain text prompts.",
    color: "#0284C7",
    bg: "#DBEAFE",
    mockupItems: ["System architecture", "User flow", "ER diagram", "Process map"],
  },
  {
    id: "workshops",
    label: "Workshops",
    icon: Users,
    headline: "Run workshops that drive real outcomes.",
    description:
      "From brainstorms to retrospectives — 6,000+ templates get you started, and AI captures key decisions automatically.",
    color: "#059669",
    bg: "#D0F0C0",
    mockupItems: ["Brainstorm", "Retrospective", "Sprint planning", "Design sprint"],
  },
];

export default function UseCaseTabs() {
  const [active, setActive] = useState("research");
  const tab = tabs.find((t) => t.id === active)!;

  return (
    <section className="py-20 md:py-28 bg-white">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="text-center mb-12">
          <h2 className="text-3xl font-extrabold text-[#050038] sm:text-4xl md:text-5xl">
            Built for every kind of team work.
          </h2>
        </div>

        {/* Tab bar */}
        <div className="flex flex-wrap justify-center gap-2 mb-12">
          {tabs.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              onClick={() => setActive(id)}
              className={cn(
                "flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold transition-all",
                active === id
                  ? "bg-[#050038] text-white"
                  : "bg-[#F5F5F7] text-[#050038] hover:bg-[#E5E5E5]"
              )}
            >
              <Icon className="h-4 w-4" />
              {label}
            </button>
          ))}
        </div>

        {/* Content */}
        <div className="grid grid-cols-1 gap-12 lg:grid-cols-2 lg:items-center">
          <div>
            <h3 className="text-2xl font-extrabold text-[#050038] sm:text-3xl leading-tight">
              {tab.headline}
            </h3>
            <p className="mt-4 text-lg text-[#6B6B8D] leading-relaxed">{tab.description}</p>
          </div>

          {/* Canvas mockup */}
          <div
            className="rounded-2xl border border-[#E5E5E5] p-6 min-h-[280px]"
            style={{ backgroundColor: tab.bg }}
          >
            <div className="mb-4 flex items-center gap-2">
              <div className="h-3 w-3 rounded-full" style={{ backgroundColor: tab.color }} />
              <span className="text-xs font-semibold text-[#050038] uppercase tracking-wider">
                {tab.label} board
              </span>
            </div>
            <div className="grid grid-cols-2 gap-3">
              {tab.mockupItems.map((item) => (
                <div
                  key={item}
                  className="rounded-lg bg-white border border-[#E5E5E5] p-4 text-sm font-medium text-[#050038] shadow-sm"
                >
                  {item}
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
