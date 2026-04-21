import { CreateForm } from "../../components/CreateForm";
import { Faucet } from "../../components/Faucet";

export default function CreatePage() {
  return (
    <div className="mx-auto max-w-xl space-y-6">
      <div>
        <h1 className="text-2xl font-semibold tracking-tight">New intent</h1>
        <p className="mt-1 text-sm text-zinc-400">
          Sign a gasless intent. Solvers will compete to execute it for the
          best net value.
        </p>
      </div>
      <Faucet />
      <CreateForm />
    </div>
  );
}
