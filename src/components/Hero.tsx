import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { ArrowRight, Sparkles } from "lucide-react";
import { cn } from "@/lib/utils";

export default function Hero() {
  return (
    <section className="relative overflow-hidden bg-white pt-20 pb-16 md:pt-28 md:pb-24">
      {/* Background gradient blobs */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 left-1/2 -translate-x-1/2 w-[800px] h-[500px] rounded-full opacity-20"
        style={{
          background:
            "radial-gradient(ellipse at center, #FFD02F 0%, #FF6B35 40%, transparent 70%)",
          filter: "blur(80px)",
        }}
      />

      <div className="relative mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 text-center">
        {/* Eyebrow badge */}
        <div className="mb-6 inline-flex items-center gap-2 rounded-full border border-[#E5E5E5] bg-white px-4 py-1.5 text-sm text-[#050038] shadow-sm">
          <Sparkles className="h-3.5 w-3.5 text-[#FFD02F]" />
          <span>Introducing Miro AI Innovation Workspace</span>
        </div>

        {/* Headline */}
        <h1 className="text-4xl font-extrabold tracking-tight text-[#050038] sm:text-5xl md:text-6xl lg:text-7xl leading-[1.08]">
          The collaboration layer your AI tools are missing.
        </h1>

        {/* Subheadline */}
        <p className="mt-6 text-lg text-[#6B6B8D] sm:text-xl max-w-2xl mx-auto leading-relaxed">
          Where teams and their agents think, plan and build together.
        </p>

        {/* CTAs */}
        <div className="mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
          <Link
            href="#"
            className={cn(
              buttonVariants({ size: "lg" }),
              "bg-[#FFD02F] text-[#050038] hover:bg-[#FFDC5E] rounded-full px-8 font-semibold text-base shadow-none"
            )}
          >
            Get started free
          </Link>
          <Link
            href="#"
            className={cn(
              buttonVariants({ variant: "ghost", size: "lg" }),
              "text-[#050038] hover:bg-[#F5F5F7] rounded-full px-6 font-semibold text-base flex items-center gap-1.5"
            )}
          >
            See how it works <ArrowRight className="h-4 w-4" />
          </Link>
        </div>

        {/* Social proof */}
        <p className="mt-8 text-sm text-[#6B6B8D]">
          Free forever · No credit card required
        </p>

        {/* Hero canvas mockup */}
        <div className="mt-16 relative mx-auto max-w-5xl rounded-2xl border border-[#E5E5E5] bg-[#F5F5F7] shadow-2xl overflow-hidden aspect-[16/9]">
          {/* Toolbar */}
          <div className="absolute left-0 top-0 h-full w-12 bg-white border-r border-[#E5E5E5] flex flex-col items-center gap-3 pt-4">
            {[...Array(6)].map((_, i) => (
              <div key={i} className="w-6 h-6 rounded bg-[#E5E5E5]" />
            ))}
          </div>
          {/* Canvas area */}
          <div className="ml-12 h-full relative p-6 flex flex-wrap gap-4 content-start">
            {/* Sticky notes */}
            <div className="w-28 h-28 rounded-lg bg-[#FFD02F] shadow p-3 text-xs text-[#050038] font-medium">
              User Research
            </div>
            <div className="w-28 h-28 rounded-lg bg-[#A8EDEA] shadow p-3 text-xs text-[#050038] font-medium">
              Pain Points
            </div>
            <div className="w-28 h-28 rounded-lg bg-[#FECDD3] shadow p-3 text-xs text-[#050038] font-medium">
              Insights
            </div>
            <div className="w-28 h-28 rounded-lg bg-white border border-[#E5E5E5] shadow p-3 text-xs text-[#050038] font-medium">
              Roadmap Q1
            </div>
            {/* Connector lines */}
            <svg className="absolute top-24 left-20 w-48 h-12 pointer-events-none" aria-hidden>
              <path d="M0 6 Q 96 6 192 6" stroke="#D1D5DB" strokeWidth="2" fill="none" strokeDasharray="4 3" />
            </svg>
            {/* AI agent card */}
            <div className="absolute bottom-8 right-8 w-52 rounded-xl border border-[#E5E5E5] bg-white shadow-lg p-4">
              <div className="flex items-center gap-2 mb-2">
                <div className="w-6 h-6 rounded-full bg-[#FFD02F] flex items-center justify-center">
                  <Sparkles className="w-3 h-3 text-[#050038]" />
                </div>
                <span className="text-xs font-semibold text-[#050038]">Miro AI</span>
              </div>
              <p className="text-[11px] text-[#6B6B8D] leading-relaxed">
                Synthesizing 3 research docs into key themes…
              </p>
              <div className="mt-2 h-1.5 rounded-full bg-[#F5F5F7] overflow-hidden">
                <div className="h-full w-2/3 rounded-full bg-[#FFD02F]" />
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
