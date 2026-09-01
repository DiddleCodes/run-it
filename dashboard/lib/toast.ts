import { toast as sonnerToast } from "sonner";

const baseClass = "!rounded-[var(--radius)] !border-0 !shadow-lg !text-sm !font-medium";

export const toast = {
  success: (message: string) => sonnerToast.success(message, { className: `${baseClass} !bg-emerald-600 !text-white` }),
  error: (message: string) => sonnerToast.error(message, { className: `${baseClass} !bg-[#7A1636] !text-white` }),
  info: (message: string) => sonnerToast.message(message, { className: `${baseClass} !bg-slate-800 !text-white` }),
};
