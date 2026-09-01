import Image from "next/image";
import { ReactNode } from "react";
import { AmbientBackground } from "./ambient-background";

export function AuthShell({ children, footer }: { children: ReactNode; footer?: ReactNode }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-[#0F0B0D] relative overflow-hidden">
      <AmbientBackground />
      <div className="relative w-full max-w-sm mx-4">
        <div className="text-center mb-8">
          <div className="inline-flex w-16 h-16 rounded-2xl bg-gradient-to-br from-[#7A1636] via-[#9B2040] to-[#D99A18] items-center justify-center shadow-2xl mb-4">
            <Image src="/brand/runit-icon-mark.png" alt="RUN-It" width={40} height={40} className="drop-shadow-sm" priority />
          </div>
          <h1 className="font-fraunces text-3xl font-semibold text-white">
            RUN-<span className="text-[#D99A18]">It</span>
          </h1>
          <p className="text-sm text-white/40 mt-1">Internal Portal</p>
        </div>

        <div className="bg-white/5 border border-white/10 rounded-2xl p-6 backdrop-blur-sm shadow-2xl">{children}</div>

        {footer ?? <p className="text-center text-[11px] text-white/20 mt-6">RUN-It Campus Delivery · Internal Portal</p>}
      </div>
    </div>
  );
}
