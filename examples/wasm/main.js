(function() {
  "use strict";

  // DOM Elements
  const elements = {
    tabs: document.querySelectorAll(".tab"),
    panels: document.querySelectorAll(".panel"),
    toastContainer: document.getElementById("toast-container"),
    // Interpreter
    contractCode: document.getElementById("contract_code"),
    calldata: document.getElementById("calldata"),
    runInterpreter: document.getElementById("run-interpreter"),
    interpreterResult: document.getElementById("interpreter-result"),
    interpreterStatus: document.getElementById("interpreter-status"),
    // Formatter
    solidityCode: document.getElementById("solidity_code"),
    runFormatter: document.getElementById("run-formatter"),
    formatterResult: document.getElementById("formatter-result"),
    formatterStatus: document.getElementById("formatter-status"),
  };

  // Toast notification system
  function showToast(type, title, message, duration = 4000) {
    const toast = document.createElement("div");
    toast.className = `toast ${type}`;
    toast.innerHTML = `
      <div class="toast-icon">${type === "error" ? "!" : "✓"}</div>
      <div class="toast-content">
        <div class="toast-title">${title}</div>
        <div class="toast-message">${message}</div>
      </div>
      <button class="toast-close" aria-label="Close">×</button>
      <div class="toast-progress"><div class="toast-progress-bar"></div></div>
    `;

    elements.toastContainer.appendChild(toast);

    const closeBtn = toast.querySelector(".toast-close");
    const hideToast = () => {
      toast.classList.add("hiding");
      setTimeout(() => toast.remove(), 300);
    };

    closeBtn.addEventListener("click", hideToast);
    setTimeout(hideToast, duration);
  }

  // WASM state
  let wasmExports = null;
  let wasmReady = false;

  // Text encoding/decoding
  const textDecoder = new TextDecoder();
  const textEncoder = new TextEncoder();

  // Tab switching
  elements.tabs.forEach((tab) => {
    tab.addEventListener("click", () => {
      const panelId = tab.dataset.panel;

      elements.tabs.forEach((t) => t.classList.remove("active"));
      elements.panels.forEach((p) => p.classList.remove("active"));

      tab.classList.add("active");
      document.getElementById(panelId).classList.add("active");
    });
  });

  // Memory view helper
  function getView(ptr, len) {
    return new Uint8Array(wasmExports.memory.buffer, ptr, len);
  }

  // Encode JS string to WASM memory (null-terminated)
  function encodeString(str) {
    const capacity = str.length * 2 + 5;
    const ptr = wasmExports.malloc(capacity);
    if (!ptr) throw new Error("Failed to allocate memory");
    const view = getView(ptr, capacity);
    const { written } = textEncoder.encodeInto(str, view);
    view[written] = 0; // Add null terminator
    return { ptr, len: written, capacity };
  }

  // Decode string from WASM memory
  function decodeString(ptr, len) {
    if (len === 0) return "";
    return textDecoder.decode(
      new Uint8Array(wasmExports.memory.buffer, ptr, len),
    );
  }

  // Unwrap packed string (ptr + len as u64)
  function unwrapString(bigint) {
    const ptr = Number(bigint & 0xffffffffn);
    const len = Number(bigint >> 32n);
    return decodeString(ptr, len);
  }

  // Unwrap packed string and convert to hex
  function unwrapHexString(bigint) {
    const ptr = Number(bigint & 0xffffffffn);
    const len = Number(bigint >> 32n);
    if (len === 0) return "";
    const buffer = new Uint8Array(wasmExports.memory.buffer, ptr, len);
    return bytesToHex(buffer);
  }

  // Convert bytes to hex string
  function bytesToHex(bytes) {
    const hex = "0123456789abcdef";
    let result = "";
    for (let i = 0; i < bytes.length; i++) {
      result += hex[bytes[i] >> 4];
      result += hex[bytes[i] & 15];
    }
    return result;
  }

  // Update status indicator
  function setStatus(element, state, text) {
    element.className = `status ${state}`;
    element.innerHTML = `<span class="status-dot"></span>${text}`;
  }

  // Set output content
  function setOutput(element, content, isEmpty = false) {
    element.textContent = content;
    element.classList.toggle("empty", isEmpty);
  }

  // Run EVM interpreter
  function runInterpreter() {
    if (!wasmReady) {
      alert("WASM module is still loading. Please wait.");
      return;
    }

    const code = elements.contractCode.value.trim();
    if (!code) {
      setOutput(
        elements.interpreterResult,
        "Please enter contract bytecode.",
        true,
      );
      return;
    }

    try {
      const codeEncoded = encodeString(code);
      const calldataEncoded = encodeString(elements.calldata.value.trim());

      const contract = wasmExports.instanciateContract(
        calldataEncoded.ptr,
        calldataEncoded.len,
        codeEncoded.ptr,
        codeEncoded.len,
      );

      const plainHost = wasmExports.getPlainHost();
      const host = wasmExports.generateHost(plainHost);

      const result = wasmExports.runCode(contract, host);

      const hexResult = unwrapHexString(result);
      setOutput(elements.interpreterResult, hexResult || "(empty result)");

      // Cleanup
      wasmExports.free(codeEncoded.ptr);
      wasmExports.free(calldataEncoded.ptr);
    } catch (err) {
      console.error("Interpreter error:", err);
      setOutput(elements.interpreterResult, "Awaiting bytecode...", true);
    }
  }

  // Format Solidity code
  function formatSolidity() {
    if (!wasmReady) {
      alert("WASM module is still loading. Please wait.");
      return;
    }

    const source = elements.solidityCode.value;
    if (!source.trim()) {
      setOutput(elements.formatterResult, "Please enter Solidity code.", true);
      return;
    }

    try {
      const encoded = encodeString(source);
      const result = wasmExports.formatSolidity(encoded.ptr, encoded.len);
      const formatted = unwrapString(result);

      setOutput(elements.formatterResult, formatted || "(empty result)");

      // Cleanup
      wasmExports.free(encoded.ptr);
    } catch (err) {
      console.error("Formatter error:", err);
      setOutput(
        elements.formatterResult,
        "Paste your Solidity code above...",
        true,
      );
    }
  }

  // Event listeners
  elements.runInterpreter.addEventListener("click", runInterpreter);
  elements.runFormatter.addEventListener("click", formatSolidity);

  // WASM environment imports
  const wasmEnv = {
    env: {
      log: (ptr, len) => {
        console.log("[WASM]", decodeString(ptr, len));
      },
      panic: (ptr, len) => {
        const msg = decodeString(ptr, len);
        console.error("[WASM Panic]", msg);
        showToast("error", "Execution Error", msg);
        throw new Error(msg);
      },
    },
  };

  // Load WASM module
  async function initWasm() {
    try {
      const response = await fetch("./zabi_wasm.wasm");
      if (!response.ok) {
        throw new Error(`Failed to fetch WASM: ${response.status}`);
      }

      const wasm = await WebAssembly.instantiateStreaming(response, wasmEnv);
      wasmExports = wasm.instance.exports;
      wasmReady = true;

      // Update status indicators
      setStatus(elements.interpreterStatus, "ready", "Ready");
      setStatus(elements.formatterStatus, "ready", "Ready");

      // Enable buttons
      elements.runInterpreter.disabled = false;
      elements.runFormatter.disabled = false;

      // Expose for debugging
      window.wasm = wasm;

      console.log("WASM module loaded successfully");
    } catch (err) {
      console.error("Failed to load WASM:", err);

      setStatus(elements.interpreterStatus, "error", "Failed to load");
      setStatus(elements.formatterStatus, "error", "Failed to load");

      setOutput(
        elements.interpreterResult,
        `Failed to load WASM module: ${err.message}\n\nMake sure zabi_wasm.wasm is in the same directory.`,
        true,
      );
      setOutput(
        elements.formatterResult,
        `Failed to load WASM module: ${err.message}\n\nMake sure zabi_wasm.wasm is in the same directory.`,
        true,
      );
    }
  }

  // Initialize
  elements.runInterpreter.disabled = true;
  elements.runFormatter.disabled = true;
  initWasm();
})();
