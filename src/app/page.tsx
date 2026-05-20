import Navbar from "@/components/Navbar";
import Hero from "@/components/Hero";
import StatsBar from "@/components/StatsBar";
import ResearchSection from "@/components/ResearchSection";
import FeaturesGrid from "@/components/FeaturesGrid";
import UseCaseTabs from "@/components/UseCaseTabs";
import CTA from "@/components/CTA";
import Footer from "@/components/Footer";

export default function Home() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <StatsBar />
        <ResearchSection />
        <FeaturesGrid />
        <UseCaseTabs />
        <CTA />
      </main>
      <Footer />
    </>
  );
}
