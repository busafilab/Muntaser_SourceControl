import Link from "next/link";
import { buttonVariants } from "@/components/ui/button";
import { cn } from "@/lib/utils";

export default function CTA() {
  return (
    <section className="py-20 md:py-28 bg-[#050038]">
      <div className="mx-auto max-w-4xl px-4 sm:px-6 lg:px-8 text-center">
        <h2 className="text-3xl font-extrabold text-white sm:text-4xl md:text-5xl leading-tight">
          Start collaborating — for free, forever.
        </h2>
        <p className="mt-5 text-lg text-[#9999BB] max-w-xl mx-auto leading-relaxed">
          No credit card required. Unlimited team members. Upgrade when you're ready.
        </p>
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
              buttonVariants({ variant: "outline", size: "lg" }),
              "border-white/30 text-white hover:bg-white/10 rounded-full px-8 font-semibold text-base bg-transparent"
            )}
          >
            Contact sales
          </Link>
        </div>
      </div>
    </section>
  );
}
