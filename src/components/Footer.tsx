import Link from "next/link";
import { Separator } from "@/components/ui/separator";

const columns = [
  {
    heading: "Getting Started",
    links: ["Pricing", "Templates", "Partners", "Community", "Changelog"],
  },
  {
    heading: "Resources",
    links: ["Blog", "Academy", "Help Center", "Status", "Developers"],
  },
  {
    heading: "Company",
    links: ["About", "Careers", "Press", "Brand assets", "Accessibility"],
  },
  {
    heading: "Legal & Security",
    links: ["Terms", "Privacy", "Cookies", "ISO 27001", "SOC 2", "GDPR"],
  },
];

const certBadges = ["ISO 42001", "ISO 27001", "SOC 2", "GDPR"];

export default function Footer() {
  return (
    <footer className="bg-white border-t border-[#E5E5E5]">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-16">
        {/* Top row */}
        <div className="grid grid-cols-2 gap-10 md:grid-cols-4 lg:grid-cols-5">
          {/* Brand column */}
          <div className="col-span-2 md:col-span-4 lg:col-span-1">
            <div className="flex items-center gap-2 mb-4">
              <svg width="32" height="32" viewBox="0 0 36 36" fill="none" aria-label="Miro">
                <rect width="36" height="36" rx="8" fill="#FFD02F" />
                <path
                  d="M22.5 9h-3.75L15 18l-1.5-9H9.75L13.5 27h3.75L21 18l1.5 9h3.75L30 9h-3.75L24.75 18 22.5 9z"
                  fill="#050038"
                />
              </svg>
              <span className="text-lg font-bold text-[#050038] tracking-tight">miro</span>
            </div>
            <p className="text-sm text-[#6B6B8D] leading-relaxed max-w-xs">
              The AI-first visual workspace for innovation. Where teams think, plan and build together.
            </p>
            {/* Security badges */}
            <div className="mt-6 flex flex-wrap gap-2">
              {certBadges.map((badge) => (
                <span
                  key={badge}
                  className="rounded border border-[#E5E5E5] px-2 py-1 text-[10px] font-semibold text-[#6B6B8D] uppercase tracking-wide"
                >
                  {badge}
                </span>
              ))}
            </div>
          </div>

          {/* Link columns */}
          {columns.map(({ heading, links }) => (
            <div key={heading}>
              <p className="mb-4 text-xs font-bold text-[#050038] uppercase tracking-widest">
                {heading}
              </p>
              <ul className="space-y-3">
                {links.map((link) => (
                  <li key={link}>
                    <Link
                      href="#"
                      className="text-sm text-[#6B6B8D] hover:text-[#050038] transition-colors"
                    >
                      {link}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <Separator className="my-10 bg-[#E5E5E5]" />

        {/* Bottom row */}
        <div className="flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between">
          <p className="text-xs text-[#6B6B8D]">
            © {new Date().getFullYear()} Miro. All rights reserved.
          </p>
          <div className="flex gap-4">
            {["Twitter / X", "LinkedIn", "YouTube", "Instagram"].map((s) => (
              <Link key={s} href="#" className="text-xs text-[#6B6B8D] hover:text-[#050038] transition-colors">
                {s}
              </Link>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
