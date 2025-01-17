module Components.BoundedContextCard exposing (init,Model,Item,view,decoder)

import Json.Decode as Decode
import Json.Decode.Pipeline as JP

import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)

import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col
import Bootstrap.Button as Button
import Bootstrap.ButtonGroup as ButtonGroup
import Bootstrap.Utilities.Border as Border
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Badge as Badge
import Bootstrap.Utilities.Spacing as Spacing
import Bootstrap.Text as Text

import Url
import Set
import List

import Route

import Key
import BoundedContext as BoundedContext exposing (BoundedContext)
import BoundedContext.Canvas exposing (BoundedContextCanvas)
import BoundedContext.StrategicClassification as StrategicClassification
import ContextMapping.Communication as Communication exposing(ScopedCommunication)
import BoundedContext.Namespace as Namespace exposing (Namespace)
import Url.Builder


type alias Item =
  { context : BoundedContext
  , canvas : BoundedContextCanvas
  , namespaces : List Namespace
  }


type alias Model =
  { contextItem : Item
  , communication : ScopedCommunication
  }

decoder =
    Decode.succeed Item
        |> JP.custom BoundedContext.modelDecoder
        |> JP.custom BoundedContext.Canvas.modelDecoder
        |> JP.optionalAt [ "namespaces" ] (Decode.list Namespace.namespaceDecoder) []

init : ScopedCommunication -> Item -> Model
init communications item =
  { contextItem = item
  , communication = communications
  }


viewLabelAsBadge : Namespace.Label -> Html msg
viewLabelAsBadge label =
  case Url.fromString label.value of
    Just link ->
      Html.a
        [ title <| "The label '" ++ label.name ++ "' is a link and has the value '" ++ label.value ++ "'"
        , class "badge badge-info"
        , link |> Url.toString |> href, target "_blank"
        , Spacing.ml1
        ]
        [ text label.name
        , Html.span [ Spacing.ml1 ] [0x0001F517 |> Char.fromCode  |> String.fromChar |> Html.text]
        ]
    Nothing ->
        Badge.badgeInfo
          [ Spacing.ml1
          , title <| "The label '" ++ label.name ++ "' has the value '" ++ label.value ++ "'"
          ]
          [ Html.span []
            [ text <| label.name ++ " | "
            , Html.a
              [ href (
                  Route.routeToString <|
                    Route.Search
                      [ Url.Builder.string "Label.Name" label.name
                      , Url.Builder.string "Label.Value" label.value
                      ]
                    )
                , target "_blank"
                , style "color" "white"
                , style "text-decoration" "underline"
                ]
                [ text label.value]
            ]
          ]


viewPillMessage : String -> Int -> List (Grid.Column msg)
viewPillMessage caption value =
  if value > 0 then
    [ Grid.col [] [text caption]
    , Grid.col [ Col.lg2]
      [ Badge.pillWarning [] [ text (value |> String.fromInt)] ]
    ]
  else []


viewItem : ScopedCommunication -> Item -> Card.Config msg
viewItem communication { context, canvas, namespaces } =
  let
    domainBadge =
      case canvas.classification.domain |> Maybe.map StrategicClassification.domainDescription of
        Just domain -> [ Badge.badgePrimary [ title domain.description ] [ text domain.name ] ]
        Nothing -> []
    businessBadges =
      canvas.classification.business
      |> List.map StrategicClassification.businessDescription
      |> List.map (\b -> Badge.badgeSecondary [ title b.description ] [ text b.name ])
    evolutionBadge =
      case canvas.classification.evolution |> Maybe.map StrategicClassification.evolutionDescription of
        Just evolution -> [ Badge.badgeInfo [ title evolution.description ] [ text evolution.name ] ]
        Nothing -> []
    badges =
      List.concat
        [ domainBadge
        , businessBadges
        , evolutionBadge
        ]

    messages =
      [ canvas.messages.commandsHandled, canvas.messages.eventsHandled, canvas.messages.queriesHandled ]
      |> List.map Set.size
      |> List.sum
      |> viewPillMessage "Handled Messages"
      |> List.append
        ( [ canvas.messages.commandsSent, canvas.messages.eventsPublished, canvas.messages.queriesInvoked]
          |> List.map Set.size
          |> List.sum
          |> viewPillMessage "Published Messages"
        )

    dependencies =
        communication
        |> Communication.inboundCommunication
        |> Communication.collaborators
        |> List.length
        |> viewPillMessage "Inbound Communication"
        |> List.append
        ( communication
            |> Communication.outboundCommunication
            |> Communication.collaborators
            |> List.length
            |> viewPillMessage "Outbound Communication"
        )

    namespaceBlocks =
      namespaces
      |> List.map (\namespace ->
        ListGroup.li []
          [ Html.h6 []
            [ text namespace.name
            , Html.small [ class "text-muted"] [ text " Namespace" ]
            ]
          , div [] (
              namespace.labels
              |> List.map viewLabelAsBadge
            )
          ]
      )

  in
  Card.config [ Card.attrs [ class "mb-3", class "shadow" ] ]
    |> Card.block []
      [ Block.titleH4 []
        [ text (context |> BoundedContext.name)
        , Html.small [ class "text-muted", class "float-right" ]
          [ text (context |> BoundedContext.key |> Maybe.map Key.toString |> Maybe.withDefault "") ]
        ]
      , if String.length canvas.description > 0
        then Block.text [ class "text-muted"] [ text canvas.description  ]
        else Block.text [class "text-muted", class "text-center" ] [ Html.i [] [ text "No description :-(" ] ]
      , Block.custom (div [] badges)
      ]
    |> (\t ->
        if (List.append dependencies messages) |> List.isEmpty
        then t
        else t
            |> Card.block []
              [ Block.custom (Grid.row [ Row.attrs [ class "row-cols-2", class "row-cols-lg-4", class "align-items-center"]] dependencies)
              , Block.custom (Grid.row [ Row.attrs [ class "row-cols-2", class "align-items-center" ]] messages)
              ]
      )
    |> (\t ->
        if List.isEmpty namespaceBlocks
        then t
        else t |> Card.listGroup namespaceBlocks
    )



view : Model -> Card.Config msg
view { communication, contextItem } =
  viewItem communication contextItem
