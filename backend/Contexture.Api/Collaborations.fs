﻿namespace Contexture.Api

open Contexture.Api
open Contexture.Api.Aggregates
open Contexture.Api.Database
open Microsoft.AspNetCore.Http
open FSharp.Control.Tasks

open Giraffe

module Collaborations =
    module CommandEndpoints =
        open Collaboration
        open FileBasedCommandHandlers

        open System
        let private updateAndReturnCollaboration command =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                task {
                    let database = ctx.GetService<Store>()

                    match Collaboration.handle database command with
                    | Ok collaborationId ->
                        return! redirectTo false (sprintf "/api/collaborations/%O" collaborationId) next ctx
                    | Error (DomainError error) ->
                        return! RequestErrors.BAD_REQUEST (sprintf "Domain Error %A" error) next ctx
                    | Error e -> return! ServerErrors.INTERNAL_ERROR e next ctx
                }

        let defineRelationship collaborationId (command: DefineRelationship) =
            updateAndReturnCollaboration (DefineRelationship(collaborationId, command))

        let outboundConnection (command: DefineConnection) =
            updateAndReturnCollaboration (DefineOutboundConnection(Guid.NewGuid(),command))

        let inboundConnection (command: DefineConnection) =
            updateAndReturnCollaboration (DefineOutboundConnection(Guid.NewGuid(),command))

        let removeAndReturnId collaborationId =
            fun (next: HttpFunc) (ctx: HttpContext) ->
                task {
                    let database = ctx.GetService<Store>()

                    match Collaboration.handle database (RemoveConnection collaborationId) with
                    | Ok collaborationId -> return! json collaborationId next ctx
                    | Error e -> return! ServerErrors.INTERNAL_ERROR e next ctx
                }


    let getCollaborations =
        fun (next: HttpFunc) (ctx: HttpContext) ->
            let database = ctx.GetService<FileBased>()
            let collaborations = database.Read.Collaborations.All
            json collaborations next ctx

    let getCollaboration collaborationId =
        fun (next: HttpFunc) (ctx: HttpContext) ->
            let database = ctx.GetService<FileBased>()
            let document = database.Read

            let result =
                collaborationId
                |> document.Collaborations.ById
                |> Option.map json
                |> Option.defaultValue (RequestErrors.NOT_FOUND(sprintf "Collaboration %O not found" collaborationId))

            result next ctx

    let routes: HttpHandler =
        subRoute
            "/collaborations"
            (choose [ subRoutef "/%O" (fun collaborationId ->
                          choose [ GET >=> getCollaboration collaborationId
                                   POST
                                   >=> route "/relationship"
                                   >=> bindJson (CommandEndpoints.defineRelationship collaborationId)
                                   DELETE >=> CommandEndpoints.removeAndReturnId collaborationId ])
                      POST
                      >=> route "/outboundConnection"
                      >=> bindJson CommandEndpoints.outboundConnection
                      POST
                      >=> route "/inboundConnection"
                      >=> bindJson CommandEndpoints.inboundConnection
                      GET >=> getCollaborations ])
