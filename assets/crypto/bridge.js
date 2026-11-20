/* BRO's OpenPGP adapter. No network operations, key persistence or logging. */
"use strict";
const broCrypto = async (input) => {
  const p = openpgp;
  const a = JSON.parse(input);
  const config = {
    v6Keys: true,
    aeadProtect: true,
    maxDecompressedMessageSize: 256 * 1024,
  };
  const publicKey = async (armor) => {
    const key = await p.readKey({ armoredKey: armor });
    if (key.isPrivate() || key.keyPacket.version !== 6) {
      throw Error("Invalid public key");
    }
    return key;
  };
  switch (a.op) {
    case "generate": {
      const { privateKey, publicKey } = await p.generateKey({
        type: "curve25519",
        userIDs: [{ name: "BRO device" }],
        config,
      });
      return JSON.stringify({ privateKey, publicKey });
    }
    case "fingerprint":
      return (await publicKey(a.key)).getFingerprint();
    case "seal": {
      const signingKeys = await p.readPrivateKey({ armoredKey: a.secret });
      const encryptionKeys = await Promise.all(a.keys.map(publicKey));
      if (!encryptionKeys.length) throw Error("No recipients");
      return p.encrypt({
        message: await p.createMessage({ text: JSON.stringify(a.body) }),
        encryptionKeys,
        signingKeys,
        config,
      });
    }
    case "open": {
      const { data } = await p.decrypt({
        message: await p.readMessage({ armoredMessage: a.packet }),
        decryptionKeys: await p.readPrivateKey({ armoredKey: a.secret }),
        verificationKeys: await publicKey(a.signer),
        expectSigned: true,
        config,
      });
      const body = JSON.parse(data);
      for (
        const k of [
          "v",
          "id",
          "conversation",
          "sender",
          "reply",
          "purpose",
          "recipients",
          "revision",
        ]
      ) {
        if (body[k] !== a.context[k]) throw Error("Wrong message context");
      }
      if (typeof body.text !== "string") throw Error("Invalid body");
      return body.text;
    }
    default:
      throw Error("Unknown crypto operation");
  }
};
globalThis.broCrypto = broCrypto;
