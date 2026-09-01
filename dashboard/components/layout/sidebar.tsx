"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { adminNav, restaurantNav } from "./nav-config";

interface SidebarProps {
  role: "restaurant" | "admin";
  collapsed: boolean;
  onToggle: () => void;
}

export function Sidebar({ role, collapsed, onToggle }: SidebarProps) {
  const pathname = usePathname();
  const navItems = role === "admin" ? adminNav : restaurantNav;

  return (
    <aside
      className={`sidebar-transition flex flex-col h-full bg-[#1A0E12] border-r border-white/5 flex-shrink-0 ${collapsed ? "w-16" : "w-60"}`}
    >
      <div className={`flex items-center h-14 px-4 border-b border-white/5 ${collapsed ? "justify-center" : "gap-3"}`}>
        <div className="w-8 h-8 rounded-lg bg-gradient-to-br from-[#7A1636] to-[#D99A18] flex items-center justify-center flex-shrink-0">
          <span className="text-white font-bold text-sm font-fraunces">R</span>
        </div>
        {!collapsed && (
          <span className="font-fraunces font-semibold text-white text-lg tracking-tight leading-none">
            RUN-<span className="text-[#D99A18]">It</span>
          </span>
        )}
      </div>

      <nav className="flex-1 py-4 overflow-y-auto">
        {!collapsed && (
          <p className="px-4 text-[10px] font-semibold uppercase tracking-widest text-white/30 mb-2">
            {role === "admin" ? "Admin" : "Restaurant"}
          </p>
        )}
        <ul className="space-y-0.5 px-2">
          {navItems.map((item) => {
            const active = pathname === item.href || pathname.startsWith(`${item.href}/`);
            return (
              <li key={item.href}>
                <Link
                  href={item.href}
                  title={collapsed ? item.label : undefined}
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-150 relative group ${
                    active ? "bg-[#7A1636]/20 text-white nav-active-indicator" : "text-white/50 hover:text-white/80 hover:bg-white/5"
                  } ${collapsed ? "justify-center" : ""}`}
                >
                  <span className={`flex-shrink-0 ${active ? "text-[#D99A18]" : ""}`}>{item.icon}</span>
                  {!collapsed && <span>{item.label}</span>}
                  {active && !collapsed && <span className="ml-auto w-1.5 h-1.5 rounded-full bg-[#D99A18]" />}
                </Link>
              </li>
            );
          })}
        </ul>

        {!collapsed && (
          <>
            <div className="h-px bg-white/5 mx-4 my-4" />
            <ul className="space-y-0.5 px-2">
              <li>
                <Link
                  href="/component-library"
                  className={`w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-sm font-medium transition-all duration-150 ${
                    pathname === "/component-library" ? "bg-[#7A1636]/20 text-white" : "text-white/30 hover:text-white/60 hover:bg-white/5"
                  }`}
                >
                  <svg width="16" height="16" viewBox="0 0 16 16" fill="none">
                    <path d="M2 5l6-3 6 3v6l-6 3-6-3V5z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
                  </svg>
                  <span>Components</span>
                </Link>
              </li>
            </ul>
          </>
        )}
      </nav>

      <div className="p-3 border-t border-white/5">
        <button
          onClick={onToggle}
          className="w-full flex items-center justify-center p-2 rounded-lg text-white/30 hover:text-white/60 hover:bg-white/5 transition-colors"
          title={collapsed ? "Expand sidebar" : "Collapse sidebar"}
        >
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" className={`transition-transform duration-300 ${collapsed ? "rotate-180" : ""}`}>
            <path d="M10 3L6 8l4 5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
      </div>
    </aside>
  );
}
