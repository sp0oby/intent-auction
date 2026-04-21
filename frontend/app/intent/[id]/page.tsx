import { IntentDetail } from "../../../components/IntentDetail";

export default function IntentPage({ params }: { params: { id: string } }) {
  return <IntentDetail id={params.id as `0x${string}`} />;
}
