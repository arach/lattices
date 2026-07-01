import { defineSandbox } from "eve/sandbox";
import { justbash } from "eve/sandbox/just-bash";

export default defineSandbox({
  backend: justbash({ autoInstall: false }),
  description: "No-Docker local sandbox for the Lattices Dewey agent. Use authored tools for real repo work.",
});
