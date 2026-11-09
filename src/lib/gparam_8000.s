; gp_* library bank for slot address $8000 (see gparam_bank.s). MIT licence.
        opt zxnext
        include "../../include/mt32_api.inc"
        org $8000
        include "gparam_bank.s"
