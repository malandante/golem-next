; gp_* library bank for slot address $C000 (see gparam_bank.s). MIT licence.
        opt zxnext
        include "../../include/mt32_api.inc"
        org $C000
        include "gparam_bank.s"
