module Main exposing (..)

import Browser
import Browser.Navigation as Nav
import Url
import Html exposing (Html, button, div, text)
import Html.Attributes exposing (..)
import Bootstrap.CDN as CDN
import Bootstrap.Grid as Grid
import Bootstrap.Grid.Row as Row
import Bootstrap.Grid.Col as Col

import Route exposing ( Route)

import Bcc
import Overview

-- MAIN

main =
  Browser.application 
    { init = init
    , update = update
    , view = view
    , subscriptions = subscriptions
    , onUrlChange = UrlChanged
    , onUrlRequest = LinkClicked 
    }


-- MODEL

type Page 
  = NotFoundPage
  | Overview Overview.Model
  | Bcc Bcc.Model

type alias Model = 
  { key : Nav.Key
  , route : Route
  , page : Page }

initCurrentPage : ( Model, Cmd Msg ) -> ( Model, Cmd Msg )
initCurrentPage ( model, existingCmds ) =
    let
      ( currentPage, mappedPageCmds ) =
        case model.route of
          Route.NotFound ->
            ( NotFoundPage, Cmd.none )

          Route.Main ->
            let
                ( pageModel, pageCmds ) = Overview.init model.key
            in
            ( Overview pageModel, Cmd.map OverviewMsg pageCmds )
          Route.Bcc id ->
            case "http://localhost:3000/api/bccs/" ++ Bcc.idToString id |> Url.fromString of
              Just url ->
                let
                  ( pageModel, pageCmds ) = Bcc.init url
                in
                  ( Bcc pageModel, Cmd.map BccMsg pageCmds )
              Nothing ->
                ( NotFoundPage, Cmd.none )

    in
    ( { model | page = currentPage }
    , Cmd.batch [ existingCmds, mappedPageCmds ]
    )

init : () -> Url.Url -> Nav.Key -> (Model, Cmd Msg)
init _ url key =
  let  
    model =
        { route = Route.parseUrl url
        , page = NotFoundPage
        , key = key
        }
  in
    initCurrentPage ( model, Cmd.none )
 
-- UPDATE

type Msg
  = LinkClicked Browser.UrlRequest
  | UrlChanged Url.Url
  | OverviewMsg Overview.Msg
  | BccMsg Bcc.Msg


update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case (msg, model.page) of
    ( LinkClicked urlRequest, _ ) ->
      case urlRequest of
          Browser.Internal url ->
              ( model
              , Nav.pushUrl model.key (Url.toString url)
              )

          Browser.External url ->
              ( model
              , Nav.load url
              )
    ( UrlChanged url, _ ) ->
      let
        newRoute = Route.parseUrl url
      in
      ( { model | route = newRoute }, Cmd.none )
          |> initCurrentPage
    (OverviewMsg m, Overview overview) ->
      let
        (updatedModel, updatedMsg) = Overview.update m overview
      in
        ({ model | page = Overview updatedModel}, updatedMsg |> Cmd.map OverviewMsg)
    (BccMsg m, Bcc bccModel) ->
      let
        (mo, msg2) = Bcc.update m bccModel
      in
        ({ model | page = Bcc mo}, Cmd.map BccMsg msg2)
    (_, _) ->
      Debug.log (Debug.toString msg ++ Debug.toString model)
      (model, Cmd.none)
        
        
-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions _ =
  Sub.none

-- VIEW

view : Model -> Browser.Document Msg
view model =
  let 
    content = 
      case model.page of
        Bcc m ->
          Bcc.view m |> Html.map BccMsg
        Overview o ->
          Overview.view o |> Html.map OverviewMsg
        NotFoundPage ->
          text "Not Found"
  in
    { title = "Bounded Context Wizard"
    , body = 
      [ CDN.stylesheet
      , Grid.container [] 
        [ content ]
      ]
    }


