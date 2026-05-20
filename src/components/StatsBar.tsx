const stats = [
  { value: "100M+", label: "people collaborating" },
  { value: "250+", label: "apps and integrations" },
  { value: "6,000+", label: "templates" },
];

export default function StatsBar() {
  return (
    <section className="border-y border-[#E5E5E5] bg-white py-10">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 gap-8 sm:grid-cols-3 text-center">
          {stats.map((stat) => (
            <div key={stat.value} className="flex flex-col items-center gap-1">
              <span className="text-4xl font-extrabold text-[#050038]">{stat.value}</span>
              <span className="text-sm text-[#6B6B8D]">{stat.label}</span>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
