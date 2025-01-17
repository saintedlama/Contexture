module Components.BoundedContextsOfDomain exposing (..)

import Api exposing (ApiResponse, ApiResult)
import Bootstrap.Badge as Badge
import Bootstrap.Button as Button
import Bootstrap.ButtonGroup as ButtonGroup
import Bootstrap.Card as Card
import Bootstrap.Card.Block as Block
import Bootstrap.Form as Form
import Bootstrap.Form.Fieldset as Fieldset
import Bootstrap.Form.Input as Input
import Bootstrap.Form.InputGroup as InputGroup
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Col as Col
import Bootstrap.Grid.Row as Row
import Bootstrap.ListGroup as ListGroup
import Bootstrap.Modal as Modal
import Bootstrap.Text as Text
import Bootstrap.Utilities.Border as Border
import Bootstrap.Utilities.Spacing as Spacing
import BoundedContext as BoundedContext exposing (BoundedContext)
import BoundedContext.Canvas exposing (BoundedContextCanvas)
import BoundedContext.Namespace as Namespace exposing (Namespace)
import BoundedContext.StrategicClassification as StrategicClassification
import Components.BoundedContextCard as BoundedContextCard
import ContextMapping.Collaboration as Collaboration
import ContextMapping.Collaborator as Collaborator
import ContextMapping.Communication as Communication
import Dict as Dict exposing (Dict)
import Domain exposing (Domain)
import Domain.DomainId exposing (DomainId)
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Html.Events exposing (onClick)
import Http
import Json.Decode as Decode
import Json.Decode.Pipeline as JP
import Key
import List
import List.Split exposing (chunksOfLeft)
import RemoteData
import Route
import Select as Autocomplete
import Set
import Url


type alias Model =
    { config : Api.Configuration
    , domain : Domain
    , contextItems : List BoundedContextCard.Model
    }


init : Api.Configuration -> Domain -> List BoundedContextCard.Item -> Collaboration.Collaborations -> Model
init config domain items collaborations =
    let
        communication =
            Communication.asCommunication collaborations

        communicationFor { context } =
            communication
                |> Communication.communicationFor
                    (context
                        |> BoundedContext.id
                        |> Collaborator.BoundedContext
                    )
    in
    { contextItems =
        items
            |> List.map
                (\i ->
                    BoundedContextCard.init (communicationFor i) i
                )
    , config = config
    , domain = domain
    }


type Msg
    = NoOp


viewWithActions : BoundedContextCard.Model -> Card.Config Never
viewWithActions model =
    model
        |> BoundedContextCard.view
        |> Card.footer []
            [ Grid.simpleRow
                [ Grid.col [ Col.md7 ]
                    [ ButtonGroup.linkButtonGroup []
                        [ ButtonGroup.linkButton
                            [ Button.roleLink
                            , Button.attrs
                                [ href
                                    (model.contextItem.context
                                        |> BoundedContext.id
                                        |> Route.BoundedContextCanvas
                                        |> Route.routeToString
                                    )
                                ]
                            ]
                            [ text "Canvas" ]
                        , ButtonGroup.linkButton
                            [ Button.roleLink
                            , Button.attrs
                                [ href
                                    (model.contextItem.context
                                        |> BoundedContext.id
                                        |> Route.Namespaces
                                        |> Route.routeToString
                                    )
                                ]
                            ]
                            [ text "Namespaces" ]
                        ]
                    ]
                ]
            ]


view : Model -> Html Msg
view { contextItems, domain } =
    let
        cards =
            contextItems
                |> List.sortBy (\{ contextItem } -> contextItem.context |> BoundedContext.name)
                |> List.map viewWithActions
                |> chunksOfLeft 2
                |> List.map Card.deck

        contextCount =
            contextItems |> List.length |> String.fromInt
    in
    div [ Spacing.mt3 ]
        [ Html.h5 [] [ text <| contextCount ++ " Bounded Context(s) in Domain '" ++ (domain |> Domain.name) ++ "'" ]
        , div [] cards
        ]
        |> Html.map (\_ -> NoOp)
