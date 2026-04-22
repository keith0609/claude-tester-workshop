# Testcase Generator

Use when a user asks for testcases for a user story that touches integration boundaries — external services (Stripe, SendGrid, AWS SNS/SQS), event-driven flows (Kafka, EventBridge, webhooks), payment flows (checkout, refund, retry), or notification pipelines. Also use when acceptance criteria exist but edge cases, failure paths, and ordering/idempotency scenarios are not yet covered.

**Niet inzetten** voor pure unit tests van geïsoleerde functies zonder side-effects of externe aanroepen.

---

## Wanneer

Activeer deze skill wanneer een of meer van de volgende condities gelden:

- De user story integreert met ≥1 externe service (payment, notification, storage, auth)
- Flows verlopen via events of messages (queue, topic, webhook, pub/sub)
- Er acceptance criteria zijn maar geen concrete testcases
- De gebruiker vraagt naar edge cases, foutpaden, of randcondities
- Er retry-logica, idempotency, of compensating transactions in het spel zijn
- Events at-least-once afgeleverd worden en deduplicatie vereist is

---

## Input

| Veld | Verplicht | Omschrijving |
|------|-----------|--------------|
| `user_story` | ja | Vrije tekst of Gherkin-formaat van de user story |
| `acceptance_criteria` | nee | Lijst van AC's; als ontbrekend en story is ambigu: vraag ernaar vóór genereren |
| `integration_surfaces` | nee | Welke externe diensten: Stripe, SendGrid, Kafka, SQS, ... |
| `tech_stack` | nee | Taal/framework (Python/pytest, Java/JUnit, TypeScript/Jest, ...) |
| `existing_tests` | nee | Bestaande testopzet ter voorkoming van duplicaten |

Als `acceptance_criteria` ontbreekt en de story meerdere interpretaties toelaat: stel één gerichte vervolgvraag en wacht op antwoord. Genereer nooit op basis van stille aannames.

---

## Output format

Elke testcase volgt dit template:

```
### TC-[nummer]: [korte titel]

**Type:** [Unit | Integration | Contract | E2E | Chaos]
**Integratievlak:** [service of component]
**AI-foutrisico:** [regel die dit dekt — zie Regels]

**Given:** [beginsituatie, inclusief mocks/stubs/seeds en hun geconfigureerde responses]
**When:**  [actie of event dat de flow triggert]
**Then:**  [verwacht resultaat + alle relevante side-effects]

**Randcondities:**
- [specifieke waarden, grensgevallen, volgorde, timing]

**Verificatiepunten:**
- [ ] [concreet assertion — geen generieke `assert ok`]
- [ ] [log/metric/event dat expliciet gecontroleerd wordt]
```

Groepeer testcases per integratievlak. Sluit elke groep af met een **dekkingstabel**:

| Scenario | Happy path | Failure | Retry | Idempotency | Out-of-order |
|----------|:----------:|:-------:|:-----:|:-----------:|:------------:|
| [flow]   | ✓/✗        | ✓/✗     | ✓/✗   | ✓/✗         | ✓/✗          |

Sluit de volledige testset af met een **Confidence-sectie** (zie R6).

---

## Regels

### R1 — Anti-hallucinatie: Gebruik alleen expliciete of aantoonbaar afleidbare details
Verzin geen Stripe-errorcodes, SNS-attributen, HTTP-statussen of event-velden die niet in de opgegeven story, codebase of documentatie staan. Als een detail niet zeker is, markeer het inline als `[VERIFY: <aanname>]` en leg uit waarom je twijfelt. Nooit stilzwijgend invullen.

### R2 — Anti-omissie: Elke happy path vereist minimaal één bijbehorend faalpad
Een testset zonder failure-scenario's is structureel onvolledig. Verplichte faalcases per integratievlak: netwerktimeout, HTTP 4xx/5xx van de externe service, lege of misvormde response, verlopen credentials. Als een integratievlak geen faalcase heeft, voeg een expliciete waarschuwing toe: `⚠️ GEEN FAALCASE — toevoegen vóór review`.

### R3 — Anti-overgeneralisatie: Schrijf stack-specifieke, concrete assertions
Gebruik geen vage assertions zoals `assert response.ok` of `expect(result).toBeTruthy()`. Schrijf exact:
- `assert response.status_code == 422`
- `expect(stripe.refunds.create).toHaveBeenCalledWith({ charge: 'ch_abc', reason: 'requested_by_customer' })`

Generieke assertions maskeren regressies en verslaan het doel van integratietesten.

### R4 — Anti-interpretatie: Vraag door bij ambiguïteit, besliss nooit zelf
Als een AC meerdere interpretaties toelaat (bijv. "de gebruiker krijgt een melding" — maar welk kanaal? welk tijdstip?), stel één gerichte vraag:

> _"Gaat het om een synchrone UI-melding of een async notificatie via email/push?"_

Markeer onduidelijkheden in de gegenereerde testcase als `[AMBIGUITY: <omschrijving>]` zodat ze aantoonbaar zijn tijdens review.

### R5 — Anti-fabricatie: Gebruik werkelijke schema's of vraag om ze
Event-driven testcases moeten het werkelijke berichtformaat gebruiken (Kafka-topicstructuur, SQS message body, EventBridge `detail`-object). Als het schema niet is opgegeven, gebruik dan een lege placeholder:

```
event_payload: { /* SCHEMA REQUIRED — lever schema aan vóór finalisatie */ }
```

Verzin nooit een volledig event-schema. Een gefabriceerd schema maskeert contractbreuken en geeft valse zekerheid.

### R6 — Confidence-kalibratie: Maak dekkingsgaten zichtbaar
Voeg na elke testset een **Confidence-sectie** toe met drie categorieën:

- **Hoog** — testcase gebaseerd op expliciete AC of code; geen aannames
- **⚠️ Aanname** — testcase gebaseerd op redelijke afleiding; verificatie vereist
- **❌ MISSING** — scenario ontbreekt omdat input ontbrak; expliciet benoemen

Overschat nooit dekking. Als de story geen retry-logica beschrijft, schrijf dan geen retry-testcase — markeer het als `❌ MISSING` en leg uit waarom het relevant zou zijn.

### R7 — Payment-specifiek: Stripe refund-failure en retry (verplichte set)
Voor elke Stripe-refund flow zijn de volgende testcases verplicht, tenzij expliciet buiten scope verklaard:

| ID | Scenario | Verwacht gedrag |
|----|----------|-----------------|
| TC-STRIPE-RF-01 | Refund mislukt: `charge_already_refunded` | HTTP 409, geen tweede refundpoging, idempotent resultaat |
| TC-STRIPE-RF-02 | Refund mislukt: netwerktimeout (StripeConnectionError) | Exponential backoff, max 3 pogingen, daarna DLQ of alert |
| TC-STRIPE-RF-03 | Stripe retourneert `status: 'pending'` | Systeem poll of webhook-handler verwerkt statusupdate correct |
| TC-STRIPE-RF-04 | Webhook `charge.refund.updated` arriveert vóór synchrone response | Idempotency-guard voorkomt dubbele verwerking |

Verifieer altijd dat de idempotency-key correct wordt doorgegeven én dat een tweede identieke aanroep dezelfde uitkomst geeft zonder extra side-effects.

### R8 — Event-driven specifiek: Robuustheid bij volgorde, duplicaten en verlies (verplichte set)
Voor elke event-driven flow zijn de volgende scenario's verplicht:

| Scenario | Wat te testen |
|----------|---------------|
| **Out-of-order** | Event B arriveert vóór event A; eindstaat moet consistent zijn. Verifieer via sequence-guard, versie-timestamp of causality-token. |
| **Duplicaten** | Hetzelfde event twee keer afgeleverd (at-least-once delivery); idempotency-key of deduplicatie-record voorkomt dubbele side-effects. |
| **Verloren event** | Consumer crasht tussen consume en ack/commit; na herstart wordt event opnieuw verwerkt zonder dataverlies of -corruptie. |
| **Poison pill** | Invalide payload die de consumer doet crashen; DLQ vangt het op, monitoring triggert alert, overige berichten worden niet geblokkeerd. |

---

## Voorbeelden

### Voorbeeld 1 — Stripe refund na orderannulering

**Input:**
```
User story: Als klant wil ik mijn bestelling annuleren zodat ik mijn geld
            terugkrijg via de originele betaalmethode.
AC:
  1. Annulering mogelijk binnen 24 uur na plaatsing
  2. Refund geïnitieerd via Stripe
  3. Klant ontvangt bevestigingsmail
Tech stack: TypeScript / Jest / Stripe SDK
```

---

#### TC-001: Succesvolle refund na annulering

**Type:** Integration
**Integratievlak:** Stripe Refunds API
**AI-foutrisico:** R2 (happy path + faalpad verderop), R3 (concrete assertions)

**Given:** Bestelling `ord_123` in status `PAID`, Stripe charge `ch_abc`,
           annulering < 24u geleden, Stripe mock retourneert `{ id: 're_xyz', status: 'succeeded' }`
**When:** `POST /orders/ord_123/cancel`
**Then:** HTTP 200, bestellingstatus → `CANCELLED`, refund `re_xyz` opgeslagen in DB,
          bevestigingsmail verstuurd naar klant

**Verificatiepunten:**
- [ ] `response.status === 200`
- [ ] `response.body.status === 'CANCELLED'`
- [ ] `db.orders.findById('ord_123').refund_id === 're_xyz'`
- [ ] `stripe.refunds.create` aangeroepen met `{ charge: 'ch_abc', reason: 'requested_by_customer' }`
- [ ] `emailService.sendCancellationConfirmation` aangeroepen met klant-ID

---

#### TC-002: Refund mislukt — charge_already_refunded (R7 / TC-STRIPE-RF-01)

**Type:** Integration
**Integratievlak:** Stripe Refunds API
**AI-foutrisico:** R7 (Stripe refund-failure), R2 (failure path)

**Given:** Bestelling `ord_123` al eerder geannuleerd, Stripe mock gooit
           `StripeInvalidRequestError` met `code: 'charge_already_refunded'`
**When:** `POST /orders/ord_123/cancel` (tweede identieke aanroep)
**Then:** HTTP 409, body `{ error: 'ALREADY_REFUNDED' }`, bestellingstatus ongewijzigd `CANCELLED`,
          geen tweede Stripe-aanroep, geen email verstuurd

**Randcondities:**
- Idempotency-key identiek aan de eerste aanroep

**Verificatiepunten:**
- [ ] `stripe.refunds.create` exact één keer aangeroepen (over beide aanroepen samen)
- [ ] `db.orders.findById('ord_123').status === 'CANCELLED'` (niet overschreven)
- [ ] `emailService.sendCancellationConfirmation` niet aangeroepen bij tweede poging

---

#### TC-003: Stripe netwerktimeout — retry met exponential backoff (R7 / TC-STRIPE-RF-02)

**Type:** Integration / Chaos
**Integratievlak:** Stripe Refunds API
**AI-foutrisico:** R7 (retry), R6 (⚠️ backoff-waarden aanname)

**Given:** Stripe mock gooit `StripeConnectionError` bij pogingen 1 en 2,
           poging 3 retourneert `{ id: 're_xyz', status: 'succeeded' }`
**When:** `POST /orders/ord_123/cancel` met retry-middleware actief
**Then:** Refund geslaagd na 3 pogingen, bestelling `CANCELLED`, email verstuurd,
          geen duplicaat-refund aangemaakt

**Randcondities:**
- Backoff-delays: [VERIFY: configuratie van retry-library] `~1s → ~2s`
- Maximaal 3 pogingen vóór DLQ

**Verificatiepunten:**
- [ ] `stripe.refunds.create` call count `=== 3`
- [ ] Backoff-delays binnen verwachte range `[VERIFY: exact bereik]`
- [ ] Eindresultaat identiek aan TC-001
- [ ] Geen tweede refund-ID in DB

---

#### TC-004: Webhook arriveert vóór synchrone response (R7 / TC-STRIPE-RF-04)

**Type:** Integration
**Integratievlak:** Stripe webhook + Refunds API
**AI-foutrisico:** R7 (idempotency race condition)

**Given:** `charge.refund.updated` webhook arriveert met `re_xyz` vóór de synchrone
           `refunds.create`-response terugkomt bij de applicatie
**When:** Webhook-handler verwerkt de update; daarna arriveert ook de synchrone response
**Then:** Refund `re_xyz` precies één keer opgeslagen, bestellingstatus `CANCELLED`,
          tweede verwerking herkend als duplicaat en genegeerd

**Verificatiepunten:**
- [ ] `db.refunds.count({ refund_id: 're_xyz' }) === 1`
- [ ] Idempotency-guard logt `DUPLICATE_SKIPPED` voor de tweede verwerking

---

**Dekkingstabel — Stripe refund:**

| Scenario | Happy path | Failure | Retry | Idempotency | Out-of-order |
|----------|:----------:|:-------:|:-----:|:-----------:|:------------:|
| Refund flow | ✓ | ✓ | ✓ | ✓ | ✓ |

**Confidence-sectie:**

| Testcase | Zekerheid | Toelichting |
|----------|-----------|-------------|
| TC-001 | Hoog | Direct van AC; geen aannames |
| TC-002 | Hoog | AC vermeldt idempotency impliciet via Stripe-gedrag |
| TC-003 | ⚠️ Aanname | Backoff-waarden niet in AC — `[VERIFY]` geplaatst |
| TC-004 | ⚠️ Aanname | Race-condition realistisch maar niet beschreven in AC |
| Pending-status flow | ❌ MISSING | AC beschrijft geen `pending`-scenario (TC-STRIPE-RF-03) |

---

### Voorbeeld 2 — Event-driven voorraadreservering (Kafka)

**Input:**
```
User story: Als systeem wil ik OrderPlaced-events verwerken zodat voorraad
            gereserveerd wordt.
AC:
  1. Bij ontvangst van OrderPlaced wordt voorraad gereserveerd
  2. Dubbele events mogen niet tot dubbele reserveringen leiden
Tech stack: Java / JUnit 5 / Kafka
```

---

#### TC-010: Out-of-order events — InventoryReserved vóór OrderPlaced

**Type:** Integration / Chaos
**Integratievlak:** Kafka topic `order-events`
**AI-foutrisico:** R8 (out-of-order), R5 (schema vereist)

**Given:** Consumer ontvangt `InventoryReserved` (seq: 2) vóór `OrderPlaced` (seq: 1)
           Event-payload: `{ /* SCHEMA REQUIRED — lever Avro/JSON schema aan */ }`
**When:** Consumer verwerkt events in ontvangstvolgorde
**Then:** Systeem buffert of verwerpt `InventoryReserved` tot `OrderPlaced` verwerkt is;
          eindstaat: voorraad correct gereserveerd, geen ghost-reserveringen

**Verificatiepunten:**
- [ ] `inventoryService.reserve()` niet aangeroepen vóór `OrderPlaced` verwerkt
- [ ] `db.reservations.count({ order_id: 'ord_123' }) === 1`
- [ ] Log bevat `OUT_OF_ORDER_BUFFERED` of `OUT_OF_ORDER_DROPPED` voor vroeg event

---

#### TC-011: Duplicaat event — OrderPlaced twee keer afgeleverd

**Type:** Integration
**Integratievlak:** Kafka topic `order-events`
**AI-foutrisico:** R8 (duplicaten), R3 (concrete assertion op call count)

**Given:** `OrderPlaced` met `event_id: 'evt_001'` wordt twee keer op het topic geplaatst
**When:** Consumer verwerkt beide berichten
**Then:** Voorraad gereserveerd precies één keer; tweede bericht herkend als duplicaat
          via idempotency-sleutel `evt_001` en genegeerd

**Verificatiepunten:**
- [ ] `inventoryService.reserve()` call count `=== 1`
- [ ] `db.reservations.count({ order_id: 'ord_123' }) === 1`
- [ ] Log bevat `DUPLICATE_SKIPPED` voor tweede event

---

#### TC-012: Consumer crash vóór offset-commit — at-least-once herstel

**Type:** Chaos
**Integratievlak:** Kafka consumer group
**AI-foutrisico:** R8 (verloren events), R6 (⚠️ consumer-config aanname)

**Given:** Consumer ontvangt `OrderPlaced`, begint verwerking, crasht vóór offset-commit
**When:** Consumer herstart en verwerkt hetzelfde event opnieuw
**Then:** Eindstaat identiek aan scenario zonder crash; idempotency voorkomt
          dubbele reservering; geen dataverlies

**Randcondities:**
- Consumer offset-commit: `[VERIFY: manual commit geconfigureerd?]`

**Verificatiepunten:**
- [ ] Na herstart: `inventoryService.reserve()` opnieuw aangeroepen
- [ ] `db.reservations.count({ order_id: 'ord_123' }) === 1`
- [ ] Geen `DuplicateReservationException` gegooid

---

#### TC-013: Poison pill — invalide payload crasht consumer niet

**Type:** Chaos
**Integratievlak:** Kafka topic `order-events` + DLQ
**AI-foutrisico:** R8 (poison pill), R2 (failure path)

**Given:** Topic bevat een bericht met een malformed JSON-payload (ontbrekend verplicht veld)
**When:** Consumer probeert het bericht te deserialiseren
**Then:** Consumer crasht niet; bericht doorgestuurd naar DLQ `order-events-dlq`;
          monitoring-alert getriggerd; volgende berichten worden normaal verwerkt

**Verificatiepunten:**
- [ ] Consumer blijft actief na ontvangst van poison pill
- [ ] `dlq.order-events-dlq` bevat het invalide bericht
- [ ] Alert `POISON_PILL_DETECTED` zichtbaar in monitoring
- [ ] Volgende geldig event na poison pill correct verwerkt

---

**Dekkingstabel — Kafka orderverwerking:**

| Scenario | Happy path | Failure | Retry | Idempotency | Out-of-order |
|----------|:----------:|:-------:|:-----:|:-----------:|:------------:|
| OrderPlaced → reserve | ✓ | ✓ | ✗ | ✓ | ✓ |

**Confidence-sectie:**

| Testcase | Zekerheid | Toelichting |
|----------|-----------|-------------|
| TC-010 out-of-order | ⚠️ Aanname | Event-schema niet opgegeven — `[SCHEMA REQUIRED]` |
| TC-011 duplicaten | Hoog | AC beschrijft idempotency expliciet |
| TC-012 crash-herstel | ⚠️ Aanname | at-least-once aangenomen; `[VERIFY: offset-commit config]` |
| TC-013 poison pill | ⚠️ Aanname | DLQ niet vermeld in AC; aanname op basis van best practice |
| Retry na consume-fout | ❌ MISSING | Retry-beleid niet beschreven in AC; toevoegen indien relevant |
