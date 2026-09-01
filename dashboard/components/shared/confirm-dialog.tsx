import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";

interface ConfirmDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: string;
  description: string;
  confirmLabel?: string;
  onConfirm: () => void;
  destructive?: boolean;
}

export function ConfirmDialog({ open, onOpenChange, title, description, confirmLabel = "Confirm", onConfirm, destructive = false }: ConfirmDialogProps) {
  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <div className={`w-10 h-10 rounded-full flex items-center justify-center mb-1 ${destructive ? "bg-red-50" : "bg-amber-50"}`}>
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none" className={destructive ? "text-red-500" : "text-amber-500"}>
              <path d="M10 4v6M10 14v.01" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
              <path d="M9.13 2.5L1.64 16a1 1 0 00.87 1.5h15.78a1 1 0 00.87-1.5L10.87 2.5a1 1 0 00-1.74 0z" stroke="currentColor" strokeWidth="1.5" />
            </svg>
          </div>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{description}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Cancel</AlertDialogCancel>
          <AlertDialogAction
            onClick={onConfirm}
            className={destructive ? "bg-red-600 text-white hover:bg-red-700" : "bg-[var(--primary)] text-white hover:bg-[#5A0E25]"}
          >
            {confirmLabel}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}
