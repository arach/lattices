import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import StudioApp from "./StudioApp";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <StudioApp />
  </StrictMode>,
);
