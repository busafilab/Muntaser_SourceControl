import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

const navItems = [
  { label: "Product", href: "#" },
  { label: "Solutions", href: "#" },
  { label: "Resources", href: "#" },
  { label: "Pricing", href: "#" },
  { label: "Contact sales", href: "#" },
];

export default function Navbar() {
  return (
    <header className="sticky top-0 z-50 w-full border-b border-[#E5E5E5] bg-white">
      <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-4 sm:px-6 lg:px-8">
        {/* Logo */}
        <Link href="/" className="flex items-center gap-2 shrink-0">
          <svg width="36" height="36" viewBox="0 0 36 36" fill="none" aria-label="Miro">
            <rect width="36" height="36" rx="8" fill="#FFD02F" />
            <path
              d="M22.5 9h-3.75L15 18l-1.5-9H9.75L13.5 27h3.75L21 18l1.5 9h3.75L30 9h-3.75L24.75 18 22.5 9z"
              fill="#050038"
            />
          </svg>
          <span className="text-xl font-bold text-[#050038] tracking-tight">miro</span>
        </Link>

        {/* Desktop nav */}
        <nav className="hidden md:flex items-center gap-1">
          {navItems.map((item) => (
            <Link
              key={item.label}
              href={item.href}
              className="flex items-center gap-0.5 rounded-md px-3 py-2 text-sm font-medium text-[#050038] hover:bg-[#F5F5F7] transition-colors"
            >
              {item.label}
              {["Product", "Solutions", "Resources"].includes(item.label) && (
                <ChevronDown className="h-3.5 w-3.5 text-[#6B6B8D]" />
              )}
            </Link>
          ))}
        </nav>

        {/* Auth buttons */}
        <div className="flex items-center gap-2">
          <Link
            href="#"
            className="hidden sm:inline-flex text-sm font-medium text-[#050038] px-3 py-2 rounded-md hover:bg-[#F5F5F7] transition-colors"
          >
            Login
          </Link>
          <Link
            href="#"
            className={cn(
              buttonVariants({ size: "default" }),
              "bg-[#050038] text-white hover:bg-[#1A1A4E] rounded-full px-5 text-sm font-semibold"
            )}
          >
            Get started free
          </Link>
        </div>
      </div>
    </header>
  );
}
