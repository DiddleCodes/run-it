import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth/session";

export default async function RootPage() {
  const session = await getSession();
  if (!session) redirect("/login");
  redirect(session.role === "admin" ? "/admin/overview" : session.accountType === "restaurant" ? "/restaurant/overview" : "/login");
}
