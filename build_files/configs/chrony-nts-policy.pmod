# Allow RSA-2048 in GnuTLS certificate chains.
# Several NTS time servers (nts.netnod.se, ptbtime1.ptb.de, time.dfm.dk,
# time.cifelli.xyz) use Let's Encrypt intermediates with RSA-2048, which are
# rejected by the FUTURE crypto policy (requires RSA >= 3072).
# This module relaxes only GnuTLS's RSA key-size floor so chrony can complete
# NTS handshakes; all other FUTURE constraints remain in effect.
min_rsa_size@gnutls = 2048
