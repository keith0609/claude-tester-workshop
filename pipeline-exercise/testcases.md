# Testcases — STORE-1234 Order Cancel Feature

## TC-001: Happy path cancel binnen 60-minuten venster
- **Precondities**: order geplaatst, minder dan 60 minuten geleden
- **Stappen**: klant klikt Cancel-knop op order-pagina
- **Verwacht resultaat**: order status wordt "Cancelled", refund wordt gestart, bevestigingsmail verstuurd binnen 5 min

## TC-002: Cancel-poging op 60:00 cut-off
- **Precondities**: order geplaatst, exact 60:00 minuten geleden
- **Stappen**: klant klikt Cancel-knop
- **Verwacht resultaat**: response is ambigu volgens spec — moet expliciet gedocumenteerd zijn (inclusief of exclusief)

## TC-003: Cancel-poging na 60:00
- **Precondities**: order geplaatst, 60:01 minuten geleden
- **Stappen**: klant klikt Cancel-knop
- **Verwacht resultaat**: Cancel-knop is disabled in UI, backend geeft 403 Forbidden

## TC-004: Dubbelklik preventie
- **Precondities**: order nog binnen cut-off
- **Stappen**: klant dubbelklikt Cancel-knop binnen 500ms
- **Verwacht resultaat**: slechts één cancel wordt verwerkt (idempotent), één bevestigingsmail

## TC-005: Stripe async refund failure
- **Precondities**: cancel geaccepteerd, Stripe refund gestart
- **Stappen**: Stripe webhook meldt refund failure na 2 dagen
- **Verwacht resultaat**: 3× retry met exponential backoff, bij definitieve failure rollback naar uncancelled status, error-mail naar klant, ops gealerteerd
