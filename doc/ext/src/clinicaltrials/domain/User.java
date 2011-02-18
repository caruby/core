package clinicaltrials.domain;

import java.util.Collection;
import java.util.HashSet;

public class User extends DomainObject
{
    /**
     * the User properties.
     */
    private String login;
    public User()
    {
    }

    /**
     * @return the User login
     */
    public String getLogin()
    {
        return login;
    }

    /**
     * @param login the login to set
     */
    public void setLogin(String login)
    {
        this.login = login;
    }
}
