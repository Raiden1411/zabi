(function () {
	const contract_code = document.getElementById("contract_code");
	const calldata = document.getElementById("calldata");

	const run = document.getElementById("run");
	run.onclick = runInterpreter;

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
	function unwrapHexString(bigint) {
		const ptr = Number(bigint & 0xffffffffn);
		const len = Number(bigint >> 32n);
		const buffer = new Uint8Array(wasm_exports.memory.buffer, ptr, len);

		return byteToHex(buffer);
	}

	const byteToHex = (byte) => {
		const key = "0123456789abcdef";
		let bytes = new Uint8Array(byte);
		let newHex = "";
		let currentChar = 0;
		for (let i = 0; i < bytes.length; i++) {
			currentChar = bytes[i] >> 4;
			newHex += key[currentChar];
			currentChar = bytes[i] & 15;
			newHex += key[currentChar];
		}
		return newHex;
	};

	function runInterpreter() {
		const code = contract_code.value;
		const call = calldata.textContent;

		const [ptr, len] = encodeString(code);
		const [pointer, length] = encodeString(call ? call : "");

		const contract = wasm_exports.instanciateContract(
			pointer,
			length,
			ptr,
			len,
		);
		const host = wasm_exports.generateHost(wasm_exports.getPlainHost());

		const result = wasm_exports.runCode(contract, host);
		const str = unwrapHexString(result);
		document.getElementById("result").textContent = str;

		wasm_exports.free(ptr);
		wasm_exports.free(pointer);
	}

	// Instantiate WASM module and run our test code.
	WebAssembly.instantiateStreaming(wasm_promise, {
		env: {
			// We export this function to WASM land.
			log: (ptr, len) => {
				const msg = decodeString(ptr, len);
				console.log(msg);
			},
		},
	}).then((wasm_binary) => {
		wasm_exports = wasm_binary.instance.exports;
		window.wasm = wasm_binary; // for debugging
	});
})();
