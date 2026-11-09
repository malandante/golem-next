; gp_* library bank for slot address $4000 (see gparam_bank.s). MIT licence.
        opt zxnext
        include "../../include/mt32_api.inc"
        org $4000
        include "gparam_bank.s"
