export function AmbientBackground() {
  return (
    <div className="absolute inset-0 overflow-hidden pointer-events-none">
      <div className="orb-1 absolute top-[-20%] left-[-10%] w-[600px] h-[600px] rounded-full bg-[#7A1636]/20 blur-[100px]" />
      <div className="orb-2 absolute bottom-[-20%] right-[-10%] w-[500px] h-[500px] rounded-full bg-[#D99A18]/15 blur-[100px]" />
      <div className="orb-3 absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[400px] h-[400px] rounded-full bg-[#5A0E25]/10 blur-[80px]" />
      <div
        className="absolute inset-0 opacity-[0.04]"
        style={{
          backgroundImage:
            "linear-gradient(rgba(255,255,255,0.8) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.8) 1px, transparent 1px)",
          backgroundSize: "60px 60px",
        }}
      />
    </div>
  );
}
