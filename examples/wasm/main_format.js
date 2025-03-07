(function () {
	const code = document.getElementById("code");

	const run = document.getElementById("run");
	run.onclick = formatCode;

	let wasm_promise = fetch("./zabi_wasm.wasm");
	var wasm_exports = null;

	const text_decoder = new TextDecoder();
	const text_encoder = new TextEncoder();

	// Convenience function to prepare a typed byte array
	// from a pointer and a length into WASM memory.
	function getView(ptr, len) {
		return new Uint8Array(wasm_exports.memory.buffer, ptr, len);
	}

	// JS strings are UTF-16 and have to be encoded into an
	// UTF-8 typed byte array in WASM memory.
	function encodeString(str) {
		const capacity = str.length * 2 + 5; // As per MDN
		const ptr = wasm_exports.malloc(capacity);
		const { written } = text_encoder.encodeInto(str, getView(ptr, capacity));
		return [ptr, written, capacity];
	}

	// Decodes the string type produced from zig.
	function decodeString(ptr, len) {
		if (len === 0) return "";
		return text_decoder.decode(
			new Uint8Array(wasm_exports.memory.buffer, ptr, len),
		);
	}

	// Unwraps the string type produced from zig.
	function unwrapString(bigint) {
		const ptr = Number(bigint & 0xffffffffn);
		const len = Number(bigint >> 32n);

		return decodeString(ptr, len);
	}

	function formatCode() {
		const source = code.value;
		const [ptr, len] = encodeString(source);

		const result = wasm_exports.formatSolidity(ptr, len);

		const str = unwrapString(result);
		console.log(str);
		document.getElementById("result").textContent = str;
	}

	// Instantiate WASM module and run our test code.
	WebAssembly.instantiateStreaming(wasm_promise, {
		env: {
			// We export this function to WASM land.
			log: (ptr, len) => {
				const msg = decodeString(ptr, len);
				console.log(msg);
			},
			panic: function (ptr, len) {
				const msg = decodeString(ptr, len);
				throw new Error("panic: " + msg);
			},
		},
	}).then((wasm_binary) => {
		wasm_exports = wasm_binary.instance.exports;
		window.wasm = wasm_binary; // for debugging
	});
})();
