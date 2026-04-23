# STORE-1234 — Order Cancel Feature

## User Story
Als klant wil ik mijn bestelling kunnen annuleren tot 1 uur na plaatsing,
zodat ik fouten kan corrigeren.
Na annulering krijg ik een bevestigingsmail binnen 5 min en wordt het bedrag
binnen 3 werkdagen teruggestort.

## Architectuur
[Web client] -> POST /api/orders/{id}/cancel
[Order Service] -> [Payment Service] -> Stripe API (async)
[Order Service] -> [Message Queue] -> [Notification Service] -> mail
[Order Service] -> [Audit Log Service]
## Acceptatiecriteria
1. Cancel mogelijk tot exact 60:00 minuten na order placement
2. Na 60:00 is cancel-knop disabled + backend geeft 403
3. Bevestigingsmail binnen 5 minuten
4. Stripe refund gestart. Async falen: 3x retry met exponential backoff
5. Als Stripe definitief faalt: cancel teruggedraaid, klant krijgt error-mail
6. Dubbelklik = 1 cancel (idempotent)
7. 2 apparaten tegelijk = 1 cancel, ander krijgt error
8. Refund binnen 3 werkdagen op bankrekening

## Niet-functionele eisen
- GDPR: notification-data na 30 dagen geanonimiseerd
- Audit trail: elke cancel-poging gelogd
- Performance: cancel-endpoint < 500ms p95 onder load

## Bekende spanning in de requirements
Criterium 1 (cancel tot 60:00) botst met criterium 5 (Stripe definitief falen
kan pas na meerdere werkdagen duidelijk zijn). Wat is de status van een cancel
waarbij de refund 5 werkdagen later definitief faalt?
Dit moet expliciet worden gedefinieerd.

## Componenten
- order-service
- payment-service (Stripe integratie)
- notification-service
- audit-service
