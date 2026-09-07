package com.digibank.app;

import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import jakarta.ws.rs.core.Response;

@Path("/index")
@Produces(MediaType.APPLICATION_JSON)
public class IndexResource {

    @GET
    public Response index() {
        String json = "{"
                + "\"name\":\"Digi Bank\","
                + "\"version\":\"1.0\","
                + "\"architecture\":\"Modular Monolith (Jakarta EE)\","
                + "\"modules\":[\"shared\",\"customer\",\"account\",\"transaction\",\"compliance\",\"index\"],"
                + "\"endpoints\":{"
                + "\"customers\":\"/api/customers\","
                + "\"accounts\":\"/api/accounts\","
                + "\"transactions\":\"/api/transactions\","
                + "\"compliance\":\"/api/compliance/validate/{amount}\""
                + "}"
                + "}";
        return Response.ok(json).build();
    }
}
