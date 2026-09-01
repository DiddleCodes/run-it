interface SkeletonBlockProps {
  className?: string;
  width?: string;
}

/** Brand-styled shimmer block — distinct from shadcn's neutral `Skeleton`, matching the prototype's loading states. */
export function SkeletonBlock({ className = "h-4", width = "100%" }: SkeletonBlockProps) {
  return <div className={`skeleton-shimmer rounded ${className}`} style={{ width }} />;
}
